using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Infrastructure.Dados;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Catálogo: produtos, imagens, tamanhos, categorias e avaliações.</summary>
public class ProdutoRepositorio : IProdutoRepositorio
{
    private readonly IConexaoFactory _conexoes;

    // Ordenações permitidas (lista branca — o texto do usuário nunca vai direto para o SQL)
    private static readonly Dictionary<string, string> Ordenacoes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["relevancia"] = "Destaque DESC, TotalAvaliacoes DESC, Id",
        ["menor-preco"] = "PrecoFinal ASC",
        ["maior-preco"] = "PrecoFinal DESC",
        ["nome"] = "Nome ASC",
        ["avaliacao"] = "NotaMedia DESC, TotalAvaliacoes DESC",
        ["novidades"] = "Id DESC"
    };

    public ProdutoRepositorio(IConexaoFactory conexoes) => _conexoes = conexoes;

    public async Task<IReadOnlyList<CategoriaResponse>> ListarCategoriasAsync()
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(
            "SELECT Id, Nome, Slug, ISNULL(Descricao, '') AS Descricao FROM dbo.Categorias WHERE Ativo = 1 ORDER BY Id", con);
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<CategoriaResponse>();
        while (await r.ReadAsync())
            lista.Add(new CategoriaResponse(r.Int("Id"), r.Str("Nome"), r.Str("Slug"), r.Str("Descricao")));
        return lista;
    }

    public async Task<IReadOnlyList<ProdutoResumoResponse>> ListarAsync(FiltroProdutos f)
    {
        var sql = "SELECT * FROM dbo.vw_CatalogoProdutos WHERE 1 = 1";
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand { Connection = con };

        if (!string.IsNullOrWhiteSpace(f.Categoria))
        {
            sql += " AND CategoriaSlug = @Categoria";
            cmd.Parameters.Add(Param("@Categoria", f.Categoria.Trim()));
        }
        if (!string.IsNullOrWhiteSpace(f.Linha))
        {
            sql += " AND Linha = @Linha";
            cmd.Parameters.Add(Param("@Linha", f.Linha.Trim()));
        }
        if (!string.IsNullOrWhiteSpace(f.Marca))
        {
            sql += " AND Marca = @Marca";
            cmd.Parameters.Add(Param("@Marca", f.Marca.Trim()));
        }
        if (f.PrecoMax is > 0)
        {
            sql += " AND PrecoFinal <= @PrecoMax";
            cmd.Parameters.Add(Param("@PrecoMax", f.PrecoMax.Value));
        }
        if (!string.IsNullOrWhiteSpace(f.Busca))
        {
            sql += " AND (Nome LIKE @Busca OR Equipe LIKE @Busca OR Modelo LIKE @Busca OR Marca LIKE @Busca OR Solado LIKE @Busca"
                 + " OR CAST(Ano AS VARCHAR(4)) = @BuscaExata)";
            var termo = f.Busca.Trim().Replace("[", "[[]").Replace("%", "[%]").Replace("_", "[_]");
            cmd.Parameters.Add(Param("@Busca", $"%{termo}%"));
            cmd.Parameters.Add(Param("@BuscaExata", f.Busca.Trim()));
        }
        if (f.Destaque == true) sql += " AND Destaque = 1";

        var ordem = Ordenacoes.TryGetValue(f.Ordem ?? "relevancia", out var o) ? o : Ordenacoes["relevancia"];
        cmd.CommandText = $"{sql} ORDER BY {ordem}";

        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<ProdutoResumoResponse>();
        while (await r.ReadAsync()) lista.Add(MapearResumo(r));
        return lista;
    }

    public async Task<ProdutoResumoResponse?> ObterResumoAsync(int id)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("SELECT * FROM dbo.vw_CatalogoProdutos WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Id", id));
        await using var r = await cmd.ExecuteReaderAsync();
        return await r.ReadAsync() ? MapearResumo(r) : null;
    }

    public async Task<IReadOnlyList<string>> ListarImagensAsync(int produtoId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(
            "SELECT Url FROM dbo.ProdutoImagens WHERE ProdutoId = @Id ORDER BY Ordem, Id", con);
        cmd.Parameters.Add(Param("@Id", produtoId));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<string>();
        while (await r.ReadAsync()) lista.Add(r.GetString(0));
        return lista;
    }

    public async Task<IReadOnlyList<TamanhoEstoqueResponse>> ListarTamanhosAsync(int produtoId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(
            "SELECT Tamanho, Quantidade FROM dbo.Estoque WHERE ProdutoId = @Id", con);
        cmd.Parameters.Add(Param("@Id", produtoId));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<TamanhoEstoqueResponse>();
        while (await r.ReadAsync()) lista.Add(new TamanhoEstoqueResponse(r.Str("Tamanho"), r.Int("Quantidade")));
        return lista;
    }

    public async Task<IReadOnlyList<AvaliacaoResponse>> ListarAvaliacoesAsync(int produtoId)
    {
        await using var con = await _conexoes.AbrirAsync();
        // Exibe apenas o primeiro nome do cliente (privacidade)
        await using var cmd = new SqlCommand(@"
            SELECT LEFT(U.Nome, CHARINDEX(' ', U.Nome + ' ') - 1) AS Cliente, A.Nota, A.Comentario, A.CriadoEm
            FROM dbo.Avaliacoes A
            INNER JOIN dbo.Usuarios U ON U.Id = A.UsuarioId
            WHERE A.ProdutoId = @Id AND A.Status = 'Publicada'
            ORDER BY A.CriadoEm DESC", con);
        cmd.Parameters.Add(Param("@Id", produtoId));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AvaliacaoResponse>();
        while (await r.ReadAsync())
            lista.Add(new AvaliacaoResponse(r.Str("Cliente"), r.Int("Nota"), r.StringOuNull("Comentario"), r.Data("CriadoEm")));
        return lista;
    }

    public async Task RegistrarAvaliacaoAsync(int produtoId, int usuarioId, int nota, string? comentario, string status)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_RegistrarAvaliacao", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@ProdutoId", produtoId));
        cmd.Parameters.Add(Param("@UsuarioId", usuarioId));
        cmd.Parameters.Add(Param("@Nota", nota));
        cmd.Parameters.Add(Param("@Comentario", comentario));
        cmd.Parameters.Add(Param("@Status", status));
        await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());
    }

    public async Task<string?> ObterSlugCategoriaAsync(int categoriaId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("SELECT Slug FROM dbo.Categorias WHERE Id = @Id AND Ativo = 1", con);
        cmd.Parameters.Add(Param("@Id", categoriaId));
        return await cmd.ExecuteScalarAsync() as string;
    }

    public async Task<int> InserirAsync(Produto p, IReadOnlyList<string> imagens)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var tx = (SqlTransaction)await con.BeginTransactionAsync();
        try
        {
            await using var cmd = new SqlCommand(@"
                INSERT INTO dbo.Produtos (CategoriaId, Nome, Modelo, Linha, Equipe, Ano, Marca, Solado, Descricao, Preco, PrecoPromocional, Imagem, Destaque)
                OUTPUT INSERTED.Id
                VALUES (@CategoriaId, @Nome, @Modelo, @Linha, @Equipe, @Ano, @Marca, @Solado, @Descricao, @Preco, @Promo, @Imagem, @Destaque);", con, tx);
            AdicionarParametrosProduto(cmd, p);
            var id = Convert.ToInt32(await TraduzirErrosAsync(() => cmd.ExecuteScalarAsync()));

            await GravarImagensAsync(con, tx, id, imagens);

            // Cria a grade de tamanhos com saldo zero (o admin abastece pelo painel)
            await using (var ctx = new SqlCommand(
                "EXEC sys.sp_set_session_context @key = N'origem', @value = N'Cadastro de produto';", con, tx))
                await ctx.ExecuteNonQueryAsync();
            foreach (var tamanho in p.GradeTamanhos)
            {
                await using var est = new SqlCommand(
                    "INSERT INTO dbo.Estoque (ProdutoId, Tamanho, Quantidade) VALUES (@Id, @Tam, 0);", con, tx);
                est.Parameters.Add(Param("@Id", id));
                est.Parameters.Add(Param("@Tam", tamanho));
                await est.ExecuteNonQueryAsync();
            }

            await tx.CommitAsync();
            return id;
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }
    }

    public async Task AtualizarAsync(Produto p, IReadOnlyList<string>? imagens)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var tx = (SqlTransaction)await con.BeginTransactionAsync();
        try
        {
            await using var cmd = new SqlCommand(@"
                UPDATE dbo.Produtos SET
                    CategoriaId = @CategoriaId, Nome = @Nome, Modelo = @Modelo, Linha = @Linha, Equipe = @Equipe,
                    Ano = @Ano, Marca = @Marca, Solado = @Solado, Descricao = @Descricao, Preco = @Preco, PrecoPromocional = @Promo,
                    Imagem = @Imagem, Destaque = @Destaque, AtualizadoEm = SYSDATETIME()
                WHERE Id = @Id;", con, tx);
            AdicionarParametrosProduto(cmd, p);
            cmd.Parameters.Add(Param("@Id", p.Id));
            await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());

            if (imagens is { Count: > 0 })
            {
                await using var del = new SqlCommand("DELETE FROM dbo.ProdutoImagens WHERE ProdutoId = @Id;", con, tx);
                del.Parameters.Add(Param("@Id", p.Id));
                await del.ExecuteNonQueryAsync();
                await GravarImagensAsync(con, tx, p.Id, imagens);
            }
            await tx.CommitAsync();
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }
    }

    public async Task<bool> DesativarAsync(int id)
    {
        await using var con = await _conexoes.AbrirAsync();
        // Exclusão lógica: preserva o histórico de pedidos que referenciam o produto
        await using var cmd = new SqlCommand(
            "UPDATE dbo.Produtos SET Ativo = 0, AtualizadoEm = SYSDATETIME() WHERE Id = @Id AND Ativo = 1", con);
        cmd.Parameters.Add(Param("@Id", id));
        return await cmd.ExecuteNonQueryAsync() > 0;
    }

    // ------------------------------------------------------------------

    private static void AdicionarParametrosProduto(SqlCommand cmd, Produto p)
    {
        cmd.Parameters.Add(Param("@CategoriaId", p.CategoriaId));
        cmd.Parameters.Add(Param("@Nome", p.Nome));
        cmd.Parameters.Add(Param("@Modelo", p.Modelo));
        cmd.Parameters.Add(Param("@Linha", p.Linha));
        cmd.Parameters.Add(Param("@Equipe", p.Equipe));
        cmd.Parameters.Add(Param("@Ano", p.Ano));
        cmd.Parameters.Add(Param("@Marca", p.Marca));
        cmd.Parameters.Add(Param("@Solado", p.Solado));
        cmd.Parameters.Add(Param("@Descricao", p.Descricao));
        cmd.Parameters.Add(Param("@Preco", p.Preco));
        cmd.Parameters.Add(Param("@Promo", p.PrecoPromocional));
        cmd.Parameters.Add(Param("@Imagem", p.Imagem));
        cmd.Parameters.Add(Param("@Destaque", p.Destaque));
    }

    private static async Task GravarImagensAsync(SqlConnection con, SqlTransaction tx, int produtoId, IReadOnlyList<string> imagens)
    {
        var ordem = 1;
        foreach (var url in imagens.Take(15))
        {
            await using var cmd = new SqlCommand(
                "INSERT INTO dbo.ProdutoImagens (ProdutoId, Url, Ordem) VALUES (@Id, @Url, @Ordem);", con, tx);
            cmd.Parameters.Add(Param("@Id", produtoId));
            cmd.Parameters.Add(Param("@Url", url.Trim()));
            cmd.Parameters.Add(Param("@Ordem", ordem++));
            await cmd.ExecuteNonQueryAsync();
        }
    }

    private static ProdutoResumoResponse MapearResumo(SqlDataReader r) => new(
        r.Int("Id"), r.Str("Nome"), r.Str("Modelo"), r.Str("Linha"), r.StringOuNull("Equipe"), r.IntOuNull("Ano"),
        r.Str("Descricao"), r.Dec("Preco"), r.DecimalOuNull("PrecoPromocional"), r.Dec("PrecoFinal"),
        r.Str("Imagem"), r.Bool("Destaque"), r.Int("CategoriaId"), r.Str("Categoria"), r.Str("CategoriaSlug"),
        r.Int("EstoqueTotal"), r.Dec("NotaMedia"), r.Int("TotalAvaliacoes"),
        r.StringOuNull("Marca"), r.StringOuNull("Solado"));
}
