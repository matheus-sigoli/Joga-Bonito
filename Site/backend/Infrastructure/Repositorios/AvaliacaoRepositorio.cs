using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Infrastructure.Dados;
using Microsoft.Data.SqlClient;
using static JogaBonito.Api.Infrastructure.Dados.SqlUtil;

namespace JogaBonito.Api.Infrastructure.Repositorios;

/// <summary>Fila de moderação das avaliações (painel admin › Avaliações).</summary>
public class AvaliacaoRepositorio : IAvaliacaoRepositorio
{
    private readonly IConexaoFactory _conexoes;

    public AvaliacaoRepositorio(IConexaoFactory conexoes) => _conexoes = conexoes;

    public async Task<IReadOnlyList<AvaliacaoAdminResponse>> ListarAsync(string? status, int limite)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP (@Limite) A.Id, A.ProdutoId, P.Nome AS Produto, U.Nome AS Cliente, A.Nota, A.Comentario,
                   A.Status, A.CriadoEm, A.MotivoModeracao, M.Email AS Moderador, A.ModeradoEm
            FROM dbo.Avaliacoes A
            INNER JOIN dbo.Produtos P ON P.Id = A.ProdutoId
            INNER JOIN dbo.Usuarios U ON U.Id = A.UsuarioId
            LEFT JOIN dbo.Usuarios M ON M.Id = A.ModeradoPor
            WHERE (@Status IS NULL OR A.Status = @Status)
            ORDER BY CASE A.Status WHEN 'Pendente' THEN 0 ELSE 1 END, A.CriadoEm DESC", con);
        cmd.Parameters.Add(Param("@Limite", limite));
        cmd.Parameters.Add(new SqlParameter("@Status", System.Data.SqlDbType.VarChar, 12) { Value = (object?)status ?? DBNull.Value });
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<AvaliacaoAdminResponse>();
        while (await r.ReadAsync())
            lista.Add(new AvaliacaoAdminResponse(r.Int("Id"), r.Int("ProdutoId"), r.Str("Produto"), r.Str("Cliente"),
                r.Int("Nota"), r.StringOuNull("Comentario"), r.Str("Status"), r.Data("CriadoEm"),
                r.StringOuNull("MotivoModeracao"), r.StringOuNull("Moderador"),
                r.IsDBNull(r.GetOrdinal("ModeradoEm")) ? null : r.Data("ModeradoEm")));
        return lista;
    }

    public async Task ModerarAsync(int avaliacaoId, string novoStatus, int adminId, string? motivo)
    {
        await using var con = await _conexoes.AbrirAsync();
        await using var cmd = new SqlCommand("dbo.sp_ModerarAvaliacao", con)
        {
            CommandType = System.Data.CommandType.StoredProcedure
        };
        cmd.Parameters.Add(Param("@AvaliacaoId", avaliacaoId));
        cmd.Parameters.Add(Param("@NovoStatus", novoStatus));
        cmd.Parameters.Add(Param("@AdminId", adminId));
        cmd.Parameters.Add(Param("@Motivo", motivo));
        await TraduzirErrosAsync(() => cmd.ExecuteNonQueryAsync());
    }
}
