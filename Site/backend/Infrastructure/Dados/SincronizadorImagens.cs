using System.Text.RegularExpressions;
using JogaBonito.Api.Application.Interfaces;
using Microsoft.Data.SqlClient;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>
/// Fotos dos produtos sem passo manual: tudo o que estiver em IMG/Produtos/&lt;id&gt;/ (jpg, png, webp,
/// avif, gif — qualquer nome) vira a galeria do produto, na ordem natural dos nomes, e a primeira é a capa.
/// Sem fotos, vale a ilustração (ilustracao.svg). Roda ao iniciar a API e sempre que algo muda nas pastas.
///
/// Só em desenvolvimento (Banco:SincronizarCatalogoLocal). O gerar_catalogo.py faz o mesmo e ainda
/// padroniza as fotos (1.jpg, 2.jpg..., até 1200 px) e leva tudo para o seed.sql da nuvem.
/// </summary>
public sealed partial class SincronizadorImagens
{
    private static readonly HashSet<string> Extensoes = new(StringComparer.OrdinalIgnoreCase)
        { ".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".jfif" };

    // Nomes seguros para ir num atributo src (letras, números, espaço, ponto, hífen, sublinhado, parênteses)
    [GeneratedRegex(@"^[\p{L}\p{N} ._()-]{1,80}$")]
    private static partial Regex NomeSeguro();

    [GeneratedRegex(@"\d+|\D+")]
    private static partial Regex Pedacos();

    private static readonly SemaphoreSlim Trava = new(1, 1);
    private readonly string _connectionString;
    private readonly ILogger _log;

    public string PastaProdutos { get; }

    public SincronizadorImagens(string connectionString, string pastaProdutos, ILogger log)
    {
        _connectionString = connectionString;
        PastaProdutos = pastaProdutos;
        _log = log;
    }

    /// <summary>Galeria que a pasta do produto define (vazia = não mexe no produto).</summary>
    public static IReadOnlyList<string> GaleriaDaPasta(string pastaProduto, int id)
    {
        if (!Directory.Exists(pastaProduto)) return Array.Empty<string>();
        var fotos = Directory.EnumerateFiles(pastaProduto)
            .Select(Path.GetFileName)
            .Where(n => n is not null && Extensoes.Contains(Path.GetExtension(n)) && !n.StartsWith("__") && NomeSeguro().IsMatch(n))
            .Select(n => n!)
            .OrderBy(n => n, ComparadorNatural.Instancia)
            .Select(n => $"../IMG/Produtos/{id}/{n}")
            .ToList();
        if (fotos.Count > 0) return fotos;
        return File.Exists(Path.Combine(pastaProduto, "ilustracao.svg"))
            ? new[] { $"../IMG/Produtos/{id}/ilustracao.svg" }
            : Array.Empty<string>();
    }

    public async Task<int> SincronizarAsync(ICacheCatalogo? cache = null, CancellationToken ct = default)
    {
        if (!Directory.Exists(PastaProdutos)) return 0;
        await Trava.WaitAsync(ct);
        try
        {
            await using var con = new SqlConnection(_connectionString);
            await con.OpenAsync(ct);

            var atuais = new Dictionary<int, List<string>>();
            await using (var cmd = new SqlCommand(
                "SELECT P.Id, I.Url FROM dbo.Produtos P LEFT JOIN dbo.ProdutoImagens I ON I.ProdutoId = P.Id ORDER BY P.Id, I.Ordem", con))
            await using (var r = await cmd.ExecuteReaderAsync(ct))
                while (await r.ReadAsync(ct))
                {
                    var id = r.GetInt32(0);
                    if (!atuais.TryGetValue(id, out var lista)) atuais[id] = lista = new List<string>();
                    if (!r.IsDBNull(1)) lista.Add(r.GetString(1));
                }

            var alterados = 0;
            foreach (var pasta in Directory.EnumerateDirectories(PastaProdutos))
            {
                if (!int.TryParse(Path.GetFileName(pasta), out var id) || !atuais.TryGetValue(id, out var atual)) continue;
                var nova = GaleriaDaPasta(pasta, id);
                if (nova.Count == 0 || nova.SequenceEqual(atual)) continue;

                await using var tx = (SqlTransaction)await con.BeginTransactionAsync(ct);
                await using (var capa = new SqlCommand(
                    "UPDATE dbo.Produtos SET Imagem = @Img, AtualizadoEm = SYSDATETIME() WHERE Id = @Id; " +
                    "DELETE FROM dbo.ProdutoImagens WHERE ProdutoId = @Id;", con, tx))
                {
                    capa.Parameters.AddWithValue("@Img", nova[0]);
                    capa.Parameters.AddWithValue("@Id", id);
                    await capa.ExecuteNonQueryAsync(ct);
                }
                for (var i = 0; i < nova.Count && i < 30; i++)
                {
                    await using var img = new SqlCommand(
                        "INSERT INTO dbo.ProdutoImagens (ProdutoId, Url, Ordem) VALUES (@Id, @Url, @Ordem)", con, tx);
                    img.Parameters.AddWithValue("@Id", id);
                    img.Parameters.AddWithValue("@Url", nova[i]);
                    img.Parameters.AddWithValue("@Ordem", (byte)(i + 1));
                    await img.ExecuteNonQueryAsync(ct);
                }
                await tx.CommitAsync(ct);
                alterados++;
            }

            if (alterados > 0)
            {
                cache?.Invalidar();
                _log.LogInformation("Fotos dos produtos atualizadas a partir das pastas: {N} produto(s).", alterados);
            }
            return alterados;
        }
        finally
        {
            Trava.Release();
        }
    }

    /// <summary>"2.jpg" antes de "10.jpg"; números antes de nomes ("1", "2", "costas", "frente").</summary>
    private sealed class ComparadorNatural : IComparer<string>
    {
        public static readonly ComparadorNatural Instancia = new();

        public int Compare(string? a, string? b)
        {
            var pa = Pedacos().Matches(Path.GetFileNameWithoutExtension(a ?? "").ToLowerInvariant());
            var pb = Pedacos().Matches(Path.GetFileNameWithoutExtension(b ?? "").ToLowerInvariant());
            for (var i = 0; i < Math.Min(pa.Count, pb.Count); i++)
            {
                var x = pa[i].Value;
                var y = pb[i].Value;
                var nx = char.IsDigit(x[0]);
                var ny = char.IsDigit(y[0]);
                int c;
                if (nx && ny) c = x.TrimStart('0').Length != y.TrimStart('0').Length
                    ? x.TrimStart('0').Length.CompareTo(y.TrimStart('0').Length)
                    : string.CompareOrdinal(x.TrimStart('0'), y.TrimStart('0'));
                else if (nx != ny) c = nx ? -1 : 1;
                else c = string.CompareOrdinal(x, y);
                if (c != 0) return c;
            }
            var porTamanho = pa.Count.CompareTo(pb.Count);
            return porTamanho != 0 ? porTamanho : string.CompareOrdinal(a, b);
        }
    }
}

/// <summary>Observa IMG/Produtos: foto nova, trocada ou apagada → galeria atualizada em ~2 s.</summary>
public sealed class ObservadorImagens : BackgroundService
{
    private readonly SincronizadorImagens _sincronizador;
    private readonly ICacheCatalogo _cache;
    private readonly ILogger<ObservadorImagens> _log;

    public ObservadorImagens(SincronizadorImagens sincronizador, ICacheCatalogo cache, ILogger<ObservadorImagens> log)
    {
        _sincronizador = sincronizador;
        _cache = cache;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        if (!Directory.Exists(_sincronizador.PastaProdutos)) return;
        using var observador = new FileSystemWatcher(_sincronizador.PastaProdutos)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size,
            EnableRaisingEvents = true
        };
        var sinal = new SemaphoreSlim(0);
        observador.Created += (_, _) => sinal.Release();
        observador.Deleted += (_, _) => sinal.Release();
        observador.Changed += (_, _) => sinal.Release();
        observador.Renamed += (_, _) => sinal.Release();

        while (!ct.IsCancellationRequested)
        {
            await sinal.WaitAsync(ct);
            await Task.Delay(TimeSpan.FromSeconds(2), ct);          // espera terminar de copiar as fotos
            while (sinal.CurrentCount > 0) await sinal.WaitAsync(ct);
            try
            {
                await _sincronizador.SincronizarAsync(_cache, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _log.LogWarning("Fotos não sincronizadas: {Erro}", ex.Message);
            }
        }
    }
}
