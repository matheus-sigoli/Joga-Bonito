namespace JogaBonito.Api.Domain.Excecoes;

/// <summary>Violação de uma regra de negócio (vira HTTP 400).</summary>
public class RegraNegocioException : Exception
{
    public RegraNegocioException(string mensagem) : base(mensagem) { }
}

/// <summary>Recurso inexistente (vira HTTP 404).</summary>
public class RecursoNaoEncontradoException : Exception
{
    public RecursoNaoEncontradoException(string mensagem) : base(mensagem) { }
}

/// <summary>Usuário autenticado sem permissão sobre o recurso (vira HTTP 403).</summary>
public class AcessoNegadoException : Exception
{
    public AcessoNegadoException(string mensagem) : base(mensagem) { }
}

/// <summary>Conta bloqueada temporariamente após senhas erradas seguidas (vira HTTP 423).</summary>
public class ContaBloqueadaException : Exception
{
    public DateTime BloqueadoAte { get; }

    public ContaBloqueadaException(DateTime bloqueadoAte)
        : base($"Conta bloqueada por segurança após várias senhas incorretas. Tente novamente após as {bloqueadoAte:HH:mm}.")
        => BloqueadoAte = bloqueadoAte;
}
