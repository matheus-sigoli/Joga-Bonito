using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Infrastructure.Dados;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Acesso à tabela Usuarios (todas as consultas parametrizadas — sem SQL Injection).</summary>
public class UsuarioRepositorio : IUsuarioRepositorio
{
    // BloqueadoAte só volta preenchido enquanto o bloqueio vale (comparação feita no relógio do banco)
    private const string Colunas =
        "Id, Nome, Email, SenhaHash, Role, Ativo, VersaoToken, CASE WHEN BloqueadoAte > SYSDATETIME() THEN BloqueadoAte END AS BloqueadoAte";
    private readonly IConexaoFactory _conexoes;

    public UsuarioRepositorio(IConexaoFactory conexoes) => _conexoes = conexoes;

    public Task<Usuario?> ObterPorEmailAsync(string email) =>
        ObterAsync($"SELECT {Colunas} FROM dbo.Usuarios WHERE Email = @valor", email);

    public Task<Usuario?> ObterPorIdAsync(int id) =>
        ObterAsync($"SELECT {Colunas} FROM dbo.Usuarios WHERE Id = @valor", id);

    public async Task<bool> EmailExisteAsync(string email)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("SELECT COUNT(1) FROM dbo.Usuarios WHERE Email = @Email", con);
        cmd.Parameters.Add(Param("@Email", email));
        return Convert.ToInt32(await cmd.ExecuteScalarAsync()) > 0;
    }

    public async Task<int> InserirAsync(Usuario usuario)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            INSERT INTO dbo.Usuarios (Nome, Email, SenhaHash, Role, AceiteLgpdEm)
            OUTPUT INSERTED.Id
            VALUES (@Nome, @Email, @SenhaHash, @Role, SYSDATETIME());", con);
        cmd.Parameters.Add(Param("@Nome", usuario.Nome));
        cmd.Parameters.Add(Param("@Email", usuario.Email));
        cmd.Parameters.Add(Param("@SenhaHash", usuario.SenhaHash));
        cmd.Parameters.Add(Param("@Role", usuario.Perfil.ToString()));
        return await TraduzirErrosAsync(async () => Convert.ToInt32(await cmd.ExecuteScalarAsync()));
    }

    public async Task<int> AtualizarSenhaAsync(int usuarioId, string novoHash)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            UPDATE dbo.Usuarios
            SET SenhaHash = @Hash, TentativasFalhas = 0, BloqueadoAte = NULL, VersaoToken = VersaoToken + 1
            OUTPUT INSERTED.VersaoToken
            WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Hash", novoHash));
        cmd.Parameters.Add(Param("@Id", usuarioId));
        return Convert.ToInt32(await cmd.ExecuteScalarAsync());
    }

    public async Task AtualizarHashAsync(int usuarioId, string novoHash)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("UPDATE dbo.Usuarios SET SenhaHash = @Hash WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Hash", novoHash));
        cmd.Parameters.Add(Param("@Id", usuarioId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<int> RevogarSessoesAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(
            "UPDATE dbo.Usuarios SET VersaoToken = VersaoToken + 1 OUTPUT INSERTED.VersaoToken WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        return Convert.ToInt32(await cmd.ExecuteScalarAsync());
    }

    public async Task<EstadoSessao?> ObterEstadoSessaoAsync(int usuarioId)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("SELECT Ativo, Role, VersaoToken FROM dbo.Usuarios WHERE Id = @Id", con);
        cmd.Parameters.Add(Param("@Id", usuarioId));
        await using var r = await cmd.ExecuteReaderAsync();
        return await r.ReadAsync() ? new EstadoSessao(r.Bool("Ativo"), r.Str("Role"), r.Int("VersaoToken")) : null;
    }

    public async Task<DateTime?> RegistrarTentativaLoginAsync(string email, bool sucesso, string? ip, string detalhe)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_RegistrarTentativaLogin", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@Email", email.Length > 120 ? email[..120] : email));
        cmd.Parameters.Add(Param("@Sucesso", sucesso));
        cmd.Parameters.Add(Param("@Ip", ip is { Length: > 45 } ? ip[..45] : ip));
        cmd.Parameters.Add(Param("@Detalhe", detalhe));
        var saida = new SqlParameter("@BloqueadoAte", System.Data.SqlDbType.DateTime2) { Direction = System.Data.ParameterDirection.Output };
        cmd.Parameters.Add(saida);
        await cmd.ExecuteNonQueryAsync();
        return saida.Value is DateTime d ? d : null;
    }

    private async Task<Usuario?> ObterAsync(string sql, object valor)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(sql, con);
        cmd.Parameters.Add(Param("@valor", valor));
        await using var r = await cmd.ExecuteReaderAsync();
        if (!await r.ReadAsync()) return null;
        return new Usuario(r.Int("Id"), r.Str("Nome"), r.Str("Email"), r.Str("SenhaHash"),
            Usuario.PerfilDeTexto(r.Str("Role")), r.Bool("Ativo"),
            r.IsDBNull(r.GetOrdinal("BloqueadoAte")) ? null : r.Data("BloqueadoAte"), r.Int("VersaoToken"));
    }
}
