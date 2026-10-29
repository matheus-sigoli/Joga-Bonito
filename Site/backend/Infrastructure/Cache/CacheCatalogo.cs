using JogaBonito.Api.Application.Interfaces;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Primitives;

namespace JogaBonito.Api.Infrastructure.Cache;

/// <summary>
/// Cache em memória da vitrine (lista de produtos, detalhe e categorias) por 30 segundos.
/// Todas as entradas ficam ligadas a um único "token de invalidação": quando o admin
/// altera produto/estoque ou um pedido baixa o estoque, <see cref="Invalidar"/> descarta
/// tudo de uma vez e a próxima consulta volta ao SQL Server.
/// </summary>
public sealed class CacheCatalogo : ICacheCatalogo
{
    public static readonly TimeSpan Duracao = TimeSpan.FromSeconds(30);

    private readonly IMemoryCache _cache;
    private CancellationTokenSource _geracao = new();
    private readonly object _trava = new();

    public CacheCatalogo(IMemoryCache cache) => _cache = cache;

    public async Task<T> ObterAsync<T>(string chave, Func<Task<T>> carregar)
    {
        if (_cache.TryGetValue(chave, out T? valor) && valor is not null)
            return valor;

        CancellationToken token;
        lock (_trava) token = _geracao.Token;

        valor = await carregar();
        _cache.Set(chave, valor, new MemoryCacheEntryOptions()
            .SetAbsoluteExpiration(Duracao)
            .SetSize(1)
            .AddExpirationToken(new CancellationChangeToken(token)));
        return valor;
    }

    public void Invalidar()
    {
        CancellationTokenSource antiga;
        lock (_trava)
        {
            antiga = _geracao;
            _geracao = new CancellationTokenSource();
        }
        antiga.Cancel();
        antiga.Dispose();
    }
}

