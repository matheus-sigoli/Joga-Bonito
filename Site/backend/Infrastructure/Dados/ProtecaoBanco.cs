using JogaBonito.Api.Infrastructure.Seguranca;
using Microsoft.Data.SqlClient;

namespace JogaBonito.Api.Infrastructure.Dados;

/// <summary>
/// Cifra os dados pessoais que ainda estão em texto aberto no banco: endereços e telefones gravados
/// antes da criptografia, dados de demonstração e bancos migrados de versões antigas.
/// Roda a cada inicialização; quando tudo já está cifrado, faz só uma consulta e sai.
/// </summary>
public static class MigradorCriptografia
{
    public static async Task ExecutarAsync(IConexaoFactory conexoes, ProtetorDados protetor, ILogger log)
    {
        try
        {
            await using var con = await conexoes.AbrirAsync();

            var enderecos = new List<(int Id, string Cep, string Rua, string Numero, string? Compl, string Bairro)>();
            await using (var cmd = new SqlCommand(@"
                SELECT TOP 5000 Id, Cep, Rua, Numero, Complemento, Bairro FROM dbo.Enderecos
                WHERE Rua NOT LIKE 'enc1:%' AND Rua <> 'Removido (LGPD)'", con))
            await using (var r = await cmd.ExecuteReaderAsync())
                while (await r.ReadAsync())
                    enderecos.Add((r.GetInt32(0), r.GetString(1).Trim(), r.GetString(2), r.GetString(3),
                        r.IsDBNull(4) ? null : r.GetString(4), r.GetString(5)));

            foreach (var e in enderecos)
            {
                await using var up = new SqlCommand(@"
                    UPDATE dbo.Enderecos SET Cep = @Cep, Rua = @Rua, Numero = @Numero, Complemento = @Compl, Bairro = @Bairro
                    WHERE Id = @Id AND Rua NOT LIKE 'enc1:%'", con);
                up.Parameters.AddWithValue("@Id", e.Id);
                up.Parameters.AddWithValue("@Cep", protetor.Proteger(e.Cep));
                up.Parameters.AddWithValue("@Rua", protetor.Proteger(e.Rua));
                up.Parameters.AddWithValue("@Numero", protetor.Proteger(e.Numero));
                up.Parameters.AddWithValue("@Compl", (object?)protetor.Proteger(e.Compl) ?? DBNull.Value);
                up.Parameters.AddWithValue("@Bairro", protetor.Proteger(e.Bairro));
                await up.ExecuteNonQueryAsync();
            }

            var telefones = new List<(int Id, string Tel)>();
            await using (var cmd = new SqlCommand(
                "SELECT TOP 5000 Id, Telefone FROM dbo.Usuarios WHERE Telefone IS NOT NULL AND Telefone NOT LIKE 'enc1:%'", con))
            await using (var r = await cmd.ExecuteReaderAsync())
                while (await r.ReadAsync()) telefones.Add((r.GetInt32(0), r.GetString(1)));

            foreach (var t in telefones)
            {
                await using var up = new SqlCommand("UPDATE dbo.Usuarios SET Telefone = @T WHERE Id = @Id", con);
                up.Parameters.AddWithValue("@Id", t.Id);
                up.Parameters.AddWithValue("@T", protetor.Proteger(t.Tel));
                await up.ExecuteNonQueryAsync();
            }

            if (enderecos.Count + telefones.Count > 0)
                log.LogInformation("Criptografia: {E} endereços e {T} telefones cifrados (AES-256-GCM).", enderecos.Count, telefones.Count);
        }
        catch (Exception ex) when (ex is SqlException or InvalidOperationException or FormatException)
        {
            // Banco fora do ar ou colunas ainda não migradas (schema.sql não rodou): tenta na próxima subida
            log.LogWarning("Criptografia dos dados antigos adiada: {Erro}", ex.Message);
        }
    }
}

/// <summary>
/// Retenção mínima (LGPD art. 15 e 16): o log de acessos guarda e-mail e IP, que só são necessários
/// para investigar incidentes recentes. Registros com mais de 180 dias são apagados uma vez por dia
/// por dbo.sp_ExpurgarRegistrosAntigos.
/// </summary>
public sealed class RotinaRetencao : BackgroundService
{
    private readonly IConexaoFactory _conexoes;
    private readonly ILogger<RotinaRetencao> _log;

    public RotinaRetencao(IConexaoFactory conexoes, ILogger<RotinaRetencao> log)
    {
        _conexoes = conexoes;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await Task.Delay(TimeSpan.FromMinutes(1), ct);   // deixa a inicialização terminar
        using var relogio = new PeriodicTimer(TimeSpan.FromHours(24));
        do
        {
            try
            {
                await using var con = await _conexoes.AbrirAsync();
                await using var cmd = new SqlCommand("dbo.sp_ExpurgarRegistrosAntigos", con)
                {
                    CommandType = System.Data.CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@Dias", 180);
                var apagados = await cmd.ExecuteScalarAsync(ct);
                if (apagados is int n && n > 0) _log.LogInformation("Retenção: {N} registros de acesso antigos apagados.", n);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _log.LogWarning("Rotina de retenção não executou: {Erro}", ex.Message);
            }
        } while (await relogio.WaitForNextTickAsync(ct));
    }
}
