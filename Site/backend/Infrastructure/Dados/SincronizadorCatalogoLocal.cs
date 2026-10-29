using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using JogaBonito.Api.Application.Interfaces;
using Microsoft.Data.SqlClient;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>
/// Leva para o SQL Server o catálogo de Javascript/catalogo-local.js — o mesmo arquivo que a vitrine
/// usa offline. Assim, quem edita esse arquivo (nome, preço, descrição, fotos, destaque) vê a mudança
/// no banco e na loja sem rodar script nenhum.
///
/// Regras:
///   * só roda com Banco:SincronizarCatalogoLocal=true (Development); em produção o catálogo chega
///     pelo seed.sql no deploy e o usuário da aplicação não tem permissão de DDL;
///   * cada produto é validado (categoria, linha, preço, tamanhos de texto, caminho da imagem dentro
///     de ../IMG/Produtos/) — um produto inválido é ignorado e registrado no log, o resto segue;
///   * a versão (SHA-256 do conteúdo) fica na propriedade estendida CatalogoLocalVersao: se o arquivo
///     não mudou, nada é gravado e as edições feitas no painel admin continuam valendo;
///   * o ESTOQUE do banco é a verdade (muda a cada venda): só tamanhos que ainda não existem são
///     criados, com a quantidade do arquivo; quantidades existentes não são sobrescritas.
/// </summary>
public sealed partial class SincronizadorCatalogoLocal
{
    private static readonly string[] Linhas = { "Clube", "Seleção", "Campo", "Society", "Futsal" };
    private static readonly string[] TamanhosCamisa = { "P", "M", "G", "GG", "XG" };

    [GeneratedRegex(@"^\.\./IMG/Produtos/\d{1,6}/[A-Za-z0-9_-]{1,60}\.(jpg|jpeg|png|webp|svg)$")]
    private static partial Regex CaminhoImagem();

    private readonly string _connectionString;
    private readonly string _arquivo;
    private readonly ILogger _log;
    private static readonly SemaphoreSlim Trava = new(1, 1);

    public SincronizadorCatalogoLocal(string connectionString, string arquivo, ILogger log)
    {
        _connectionString = connectionString;
        _arquivo = arquivo;
        _log = log;
    }

    public string Arquivo => _arquivo;

    /// <summary>Resultado de uma sincronização (também usado nos testes).</summary>
    public sealed record Resultado(bool Alterado, int Produtos, int Ignorados, string Versao);

    /// <summary>Produto lido e validado do arquivo.</summary>
    public sealed record ProdutoLocal(
        int Id, string CategoriaSlug, string Nome, string Modelo, string Linha, string? Equipe, short? Ano,
        string? Marca, string? Solado, string Descricao, decimal Preco, decimal? PrecoPromocional,
        string Imagem, bool Destaque, IReadOnlyList<string> Imagens, IReadOnlyList<(string Tamanho, int Quantidade)> Tamanhos);

    public async Task<Resultado> SincronizarAsync(ICacheCatalogo? cache = null, CancellationToken ct = default)
    {
        await Trava.WaitAsync(ct);
        try
        {
            var texto = await LerComRetentativaAsync(ct);
            var (produtos, ignorados) = Ler(texto, _log);
            var versao = Versao(produtos);

            await using var con = new SqlConnection(_connectionString);
            await con.OpenAsync(ct);

            await using (var v = new SqlCommand(
                "SELECT CAST(value AS NVARCHAR(80)) FROM sys.extended_properties " +
                "WHERE major_id = OBJECT_ID('dbo.Produtos') AND minor_id = 0 AND name = 'CatalogoLocalVersao'", con))
            {
                if (await v.ExecuteScalarAsync(ct) is string atual && atual == versao)
                    return new Resultado(false, produtos.Count, ignorados, versao);
            }

            var categorias = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            await using (var c = new SqlCommand("SELECT Slug, Id FROM dbo.Categorias", con))
            await using (var r = await c.ExecuteReaderAsync(ct))
                while (await r.ReadAsync(ct)) categorias[r.GetString(0)] = r.GetInt32(1);

            await using var tx = (SqlTransaction)await con.BeginTransactionAsync(ct);
            var gravados = 0;
            foreach (var p in produtos)
            {
                if (!categorias.TryGetValue(p.CategoriaSlug, out var categoriaId))
                {
                    ignorados++;
                    _log.LogWarning("catalogo-local.js: produto {Id} com categoria desconhecida '{Cat}' — ignorado.", p.Id, p.CategoriaSlug);
                    continue;
                }
                await GravarAsync(con, tx, p, categoriaId, ct);
                gravados++;
            }

            await using (var prop = new SqlCommand(@"
                IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID('dbo.Produtos') AND minor_id = 0 AND name = 'CatalogoLocalVersao')
                    EXEC sys.sp_updateextendedproperty @name = N'CatalogoLocalVersao', @value = @v, @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';
                ELSE
                    EXEC sys.sp_addextendedproperty @name = N'CatalogoLocalVersao', @value = @v, @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Produtos';",
                con, tx))
            {
                prop.Parameters.AddWithValue("@v", versao);
                await prop.ExecuteNonQueryAsync(ct);
            }
            await tx.CommitAsync(ct);
            cache?.Invalidar();
            _log.LogInformation("Catálogo local sincronizado com o banco: {N} produtos (versão {V}, {I} ignorados).", gravados, versao, ignorados);
            return new Resultado(true, gravados, ignorados, versao);
        }
        finally
        {
            Trava.Release();
        }
    }

    private async Task<string> LerComRetentativaAsync(CancellationToken ct)
    {
        // O editor pode estar gravando o arquivo no mesmo instante: tenta algumas vezes
        for (var tentativa = 1; ; tentativa++)
        {
            try
            {
                return await File.ReadAllTextAsync(_arquivo, Encoding.UTF8, ct);
            }
            catch (IOException) when (tentativa < 5)
            {
                await Task.Delay(300, ct);
            }
        }
    }

    // ------------------------------------------------------------------ leitura e validação
    public static (List<ProdutoLocal> Produtos, int Ignorados) Ler(string texto, ILogger? log = null)
    {
        var inicio = texto.IndexOf("JB_CATALOGO_LOCAL", StringComparison.Ordinal);
        inicio = inicio < 0 ? -1 : texto.IndexOf('[', inicio);
        if (inicio < 0)
            throw new FormatException("catalogo-local.js não contém a lista JB_CATALOGO_LOCAL = [ ... ].");

        // Lê exatamente UM valor JSON a partir do "[": o código JavaScript depois da lista é ignorado
        var bytes = Encoding.UTF8.GetBytes(texto[inicio..]);
        var leitor = new Utf8JsonReader(bytes, new JsonReaderOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
            MaxDepth = 8
        });
        using var doc = JsonDocument.ParseValue(ref leitor);
        if (doc.RootElement.ValueKind != JsonValueKind.Array)
            throw new FormatException("JB_CATALOGO_LOCAL precisa ser uma lista.");

        var lista = new List<ProdutoLocal>();
        var ids = new HashSet<int>();
        var ignorados = 0;
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            try
            {
                var p = Validar(item);
                if (!ids.Add(p.Id)) throw new FormatException("id repetido");
                lista.Add(p);
            }
            catch (Exception ex) when (ex is FormatException or InvalidOperationException or KeyNotFoundException)
            {
                ignorados++;
                var id = item.ValueKind == JsonValueKind.Object && item.TryGetProperty("id", out var i) ? i.ToString() : "?";
                log?.LogWarning("catalogo-local.js: produto {Id} ignorado — {Motivo}", id, ex.Message);
            }
        }
        return (lista, ignorados);
    }

    private static ProdutoLocal Validar(JsonElement e)
    {
        var id = e.GetProperty("id").GetInt32();
        if (id is < 1 or > 999_999) throw new FormatException("id fora da faixa");

        var slug = Texto(e, "categoriaSlug", 40)!;
        var nome = Texto(e, "nome", 100, minimo: 2)!;
        var modelo = Texto(e, "modelo", 100)!;
        var linha = Texto(e, "linha", 20)!;
        if (!Linhas.Contains(linha)) throw new FormatException($"linha '{linha}' inválida (use {string.Join(", ", Linhas)})");
        var equipe = Texto(e, "equipe", 60, opcional: true);
        var marca = Texto(e, "marca", 40, opcional: true);
        var solado = Texto(e, "solado", 40, opcional: true);
        var descricao = Texto(e, "descricao", 1000, minimo: 10)!;

        short? ano = null;
        if (e.TryGetProperty("ano", out var a) && a.ValueKind == JsonValueKind.Number)
        {
            var n = a.GetInt32();
            if (n is < 1863 or > 2100) throw new FormatException("ano inválido");
            ano = (short)n;
        }

        var preco = Math.Round(e.GetProperty("preco").GetDecimal(), 2);
        if (preco is <= 0 or > 100_000) throw new FormatException("preço inválido");
        decimal? promo = null;
        if (e.TryGetProperty("precoPromocional", out var pp) && pp.ValueKind == JsonValueKind.Number)
        {
            promo = Math.Round(pp.GetDecimal(), 2);
            if (promo <= 0 || promo >= preco) throw new FormatException("preço promocional precisa ser menor que o preço");
        }

        var imagens = new List<string>();
        if (e.TryGetProperty("imgs", out var imgs) && imgs.ValueKind == JsonValueKind.Array)
            foreach (var i in imgs.EnumerateArray().Take(12))
                imagens.Add(Imagem(i.GetString()));
        var capa = Imagem(e.GetProperty("img").GetString());
        if (imagens.Count == 0) imagens.Add(capa);

        var chuteira = slug.Equals("chuteiras", StringComparison.OrdinalIgnoreCase);
        var tamanhos = new List<(string, int)>();
        if (e.TryGetProperty("tamanhos", out var tams) && tams.ValueKind == JsonValueKind.Array)
            foreach (var t in tams.EnumerateArray())
            {
                var tam = t.GetProperty("tamanho").GetString()?.Trim().ToUpperInvariant() ?? "";
                var valido = chuteira
                    ? int.TryParse(tam, NumberStyles.None, CultureInfo.InvariantCulture, out var num) && num is >= 33 and <= 46
                    : TamanhosCamisa.Contains(tam);
                if (!valido) throw new FormatException($"tamanho '{tam}' inválido para {(chuteira ? "chuteira" : "camisa")}");
                var q = t.TryGetProperty("quantidade", out var qt) ? qt.GetInt32() : 0;
                tamanhos.Add((tam, Math.Clamp(q, 0, 9999)));
            }

        var destaque = e.TryGetProperty("destaque", out var d) && d.ValueKind == JsonValueKind.True;
        return new ProdutoLocal(id, slug, nome, modelo, linha, equipe, ano, marca, solado, descricao,
            preco, promo, capa, destaque, imagens, tamanhos);
    }

    private static string? Texto(JsonElement e, string campo, int maximo, int minimo = 1, bool opcional = false)
    {
        if (!e.TryGetProperty(campo, out var v) || v.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            if (opcional) return null;
            throw new FormatException($"campo '{campo}' obrigatório");
        }
        var s = v.GetString()?.Trim() ?? "";
        if (s.Length == 0 && opcional) return null;
        if (s.Length < minimo || s.Length > maximo)
            throw new FormatException($"'{campo}' deve ter entre {minimo} e {maximo} caracteres");
        if (s.Any(char.IsControl)) throw new FormatException($"'{campo}' tem caracteres de controle");
        return s;
    }

    /// <summary>Só caminhos de imagem dentro de IMG/Produtos — nada de URL externa, "../../" ou javascript:.</summary>
    private static string Imagem(string? url)
    {
        var u = (url ?? "").Trim();
        if (u.Length > 200 || !CaminhoImagem().IsMatch(u))
            throw new FormatException($"imagem '{u}' fora de ../IMG/Produtos/<id>/");
        return u;
    }

    public static string Versao(IEnumerable<ProdutoLocal> produtos)
    {
        var sb = new StringBuilder();
        foreach (var p in produtos.OrderBy(p => p.Id))
            sb.Append(JsonSerializer.Serialize(p with { Tamanhos = p.Tamanhos.Select(t => (t.Tamanho, 0)).ToList() }))
              .Append(string.Join(",", p.Tamanhos.Select(t => t.Tamanho))).Append('\n');
        return "local-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString())))[..16].ToLowerInvariant();
    }

    // ------------------------------------------------------------------ gravação
    private static async Task GravarAsync(SqlConnection con, SqlTransaction tx, ProdutoLocal p, int categoriaId, CancellationToken ct)
    {
        const string sql = @"
            IF EXISTS (SELECT 1 FROM dbo.Produtos WHERE Id = @Id)
                UPDATE dbo.Produtos SET CategoriaId = @Cat, Nome = @Nome, Modelo = @Modelo, Linha = @Linha,
                       Equipe = @Equipe, Ano = @Ano, Marca = @Marca, Solado = @Solado, Descricao = @Desc,
                       Preco = @Preco, PrecoPromocional = @Promo, Imagem = @Img, Destaque = @Dest,
                       AtualizadoEm = SYSDATETIME()
                WHERE Id = @Id;
            ELSE
            BEGIN
                SET IDENTITY_INSERT dbo.Produtos ON;
                INSERT INTO dbo.Produtos (Id, CategoriaId, Nome, Modelo, Linha, Equipe, Ano, Marca, Solado, Descricao,
                                          Preco, PrecoPromocional, Imagem, Destaque)
                VALUES (@Id, @Cat, @Nome, @Modelo, @Linha, @Equipe, @Ano, @Marca, @Solado, @Desc, @Preco, @Promo, @Img, @Dest);
                SET IDENTITY_INSERT dbo.Produtos OFF;
            END
            DELETE FROM dbo.ProdutoImagens WHERE ProdutoId = @Id;";

        await using (var cmd = new SqlCommand(sql, con, tx))
        {
            cmd.Parameters.AddWithValue("@Id", p.Id);
            cmd.Parameters.AddWithValue("@Cat", categoriaId);
            cmd.Parameters.AddWithValue("@Nome", p.Nome);
            cmd.Parameters.AddWithValue("@Modelo", p.Modelo);
            cmd.Parameters.AddWithValue("@Linha", p.Linha);
            cmd.Parameters.AddWithValue("@Equipe", (object?)p.Equipe ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Ano", (object?)p.Ano ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Marca", (object?)p.Marca ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Solado", (object?)p.Solado ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Desc", p.Descricao);
            cmd.Parameters.AddWithValue("@Preco", p.Preco);
            cmd.Parameters.AddWithValue("@Promo", (object?)p.PrecoPromocional ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Img", p.Imagem);
            cmd.Parameters.AddWithValue("@Dest", p.Destaque);
            await cmd.ExecuteNonQueryAsync(ct);
        }

        for (var i = 0; i < p.Imagens.Count; i++)
        {
            await using var img = new SqlCommand(
                "INSERT INTO dbo.ProdutoImagens (ProdutoId, Url, Ordem) VALUES (@Id, @Url, @Ordem)", con, tx);
            img.Parameters.AddWithValue("@Id", p.Id);
            img.Parameters.AddWithValue("@Url", p.Imagens[i]);
            img.Parameters.AddWithValue("@Ordem", (byte)(i + 1));
            await img.ExecuteNonQueryAsync(ct);
        }

        foreach (var (tamanho, quantidade) in p.Tamanhos)
        {
            await using var est = new SqlCommand(@"
                IF NOT EXISTS (SELECT 1 FROM dbo.Estoque WHERE ProdutoId = @Id AND Tamanho = @Tam)
                    INSERT INTO dbo.Estoque (ProdutoId, Tamanho, Quantidade) VALUES (@Id, @Tam, @Qtd);", con, tx);
            est.Parameters.AddWithValue("@Id", p.Id);
            est.Parameters.AddWithValue("@Tam", tamanho);
            est.Parameters.AddWithValue("@Qtd", quantidade);
            await est.ExecuteNonQueryAsync(ct);
        }
    }
}

/// <summary>
/// Em desenvolvimento, observa o catalogo-local.js com a API ligada: salvou o arquivo,
/// o banco e a vitrine são atualizados em ~2 segundos, sem reiniciar nada.
/// </summary>
public sealed class ObservadorCatalogoLocal : BackgroundService
{
    private readonly SincronizadorCatalogoLocal _sincronizador;
    private readonly ICacheCatalogo _cache;
    private readonly ILogger<ObservadorCatalogoLocal> _log;

    private readonly SincronizadorImagens? _imagens;

    public ObservadorCatalogoLocal(SincronizadorCatalogoLocal sincronizador, ICacheCatalogo cache,
        ILogger<ObservadorCatalogoLocal> log, SincronizadorImagens? imagens = null)
    {
        _sincronizador = sincronizador;
        _cache = cache;
        _log = log;
        _imagens = imagens;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var pasta = Path.GetDirectoryName(_sincronizador.Arquivo);
        if (pasta is null || !Directory.Exists(pasta)) return;

        using var observador = new FileSystemWatcher(pasta, Path.GetFileName(_sincronizador.Arquivo))
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
            EnableRaisingEvents = true
        };
        var sinal = new SemaphoreSlim(0);
        void Mudou(object? _, FileSystemEventArgs __) => sinal.Release();
        observador.Changed += Mudou;
        observador.Created += Mudou;
        observador.Renamed += (s, e) => Mudou(s, e);

        while (!ct.IsCancellationRequested)
        {
            await sinal.WaitAsync(ct);
            await Task.Delay(TimeSpan.FromSeconds(2), ct);       // espera o editor terminar de gravar
            while (sinal.CurrentCount > 0) await sinal.WaitAsync(ct);
            try
            {
                var r = await _sincronizador.SincronizarAsync(_cache, ct);
                if (r.Alterado) _log.LogInformation("catalogo-local.js alterado: {N} produtos atualizados no banco.", r.Produtos);
                // As fotos que estão nas pastas continuam valendo mais que a lista do arquivo
                if (r.Alterado && _imagens is not null) await _imagens.SincronizarAsync(_cache, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _log.LogWarning("catalogo-local.js não foi sincronizado: {Erro}", ex.Message);
            }
        }
    }
}
