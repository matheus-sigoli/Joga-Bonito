using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Infrastructure.Dados;
using JogaBonito.Api.Infrastructure.Seguranca;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Consultas do titular sobre os próprios dados e a anonimização (sp_AnonimizarUsuario).</summary>
public class PrivacidadeRepositorio : IPrivacidadeRepositorio
{
    private readonly IConexaoFactory _conexoes;
    private readonly ProtetorDados _protetor;

    public PrivacidadeRepositorio(IConexaoFactory conexoes, ProtetorDados protetor)
    {
        _conexoes = conexoes;
        _protetor = protetor;
    }

    public async Task<ContaResponse?> ObterContaAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(
            "SELECT Id, Nome, Email, Telefone, Role, CriadoEm, AceiteLgpdEm FROM dbo.Usuarios WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        await using var r = await cmd.ExecuteReaderAsync();
        if (!await r.ReadAsync()) return null;
        return new ContaResponse(r.Int("Id"), r.Str("Nome"), r.Str("Email"), _protetor.Abrir(r.StringOuNull("Telefone")), r.Str("Role"),
            r.Data("CriadoEm"), r.IsDBNull(r.GetOrdinal("AceiteLgpdEm")) ? null : r.Data("AceiteLgpdEm"));
    }

    public async Task<IReadOnlyList<EnderecoResponse>> ListarEnderecosAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT Cep, Rua, Numero, Complemento, Bairro, Cidade, Estado
            FROM dbo.Enderecos WHERE UsuarioId = @Id ORDER BY Id", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<EnderecoResponse>();
        while (await r.ReadAsync())
            lista.Add(new EnderecoResponse(_protetor.Abrir(r.Str("Cep"))!, _protetor.Abrir(r.Str("Rua"))!,
                _protetor.Abrir(r.Str("Numero"))!, _protetor.Abrir(r.StringOuNull("Complemento")),
                _protetor.Abrir(r.Str("Bairro"))!, r.Str("Cidade"), r.Str("Estado")));
        return lista;
    }

    public async Task<IReadOnlyList<AvaliacaoPessoalResponse>> ListarAvaliacoesAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT P.Nome AS Produto, A.Nota, A.Comentario, A.Status, A.CriadoEm
            FROM dbo.Avaliacoes A INNER JOIN dbo.Produtos P ON P.Id = A.ProdutoId
            WHERE A.UsuarioId = @Id ORDER BY A.CriadoEm DESC", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AvaliacaoPessoalResponse>();
        while (await r.ReadAsync())
            lista.Add(new AvaliacaoPessoalResponse(r.Str("Produto"), r.Int("Nota"), r.StringOuNull("Comentario"),
                r.Str("Status"), r.Data("CriadoEm")));
        return lista;
    }

    public async Task<IReadOnlyList<AcessoResponse>> ListarAcessosAsync(int usuarioId, int limite)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP (@Limite) Id, Email, Ip, Sucesso, Detalhe, Data
            FROM dbo.LogAcessos WHERE UsuarioId = @Id ORDER BY Id DESC", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        cmd.Parameters.Add(Param("@Limite", limite));
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AcessoResponse>();
        while (await r.ReadAsync())
            lista.Add(new AcessoResponse(Convert.ToInt64(r["Id"]), r.Str("Email"), r.StringOuNull("Ip"),
                r.Bool("Sucesso"), r.StringOuNull("Detalhe"), r.Data("Data")));
        return lista;
    }

    public async Task AnonimizarAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_AnonimizarUsuario", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@UsuarioId", usuarioId));
        await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());
    }
}
