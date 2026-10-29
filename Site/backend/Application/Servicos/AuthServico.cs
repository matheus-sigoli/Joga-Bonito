using JogaBonito.Api.Application.DTOs;
using JogaBonito.Api.Application.Interfaces;
using JogaBonito.Api.Domain.Entidades;
using JogaBonito.Api.Domain.Excecoes;

namespace JogaBonito.Api.Application.Servicos;

/// <summary>
/// Regras de autenticação e cadastro de clientes.
/// Proteção contra força bruta em duas camadas: limite de requisições por IP (rate limiter)
/// e bloqueio da CONTA por 15 minutos após 5 senhas erradas seguidas (regra no banco).
/// </summary>
public class AuthServico
{
    private readonly IUsuarioRepositorio _usuarios;
    private readonly IHasherSenha _hasher;
    private readonly IGeradorToken _tokens;

    public AuthServico(IUsuarioRepositorio usuarios, IHasherSenha hasher, IGeradorToken tokens)
    {
        _usuarios = usuarios;
        _hasher = hasher;
        _tokens = tokens;
    }

    public async Task<LoginResponse> LoginAsync(LoginRequest request, string? ip = null)
    {
        var email = Usuario.NormalizarEmail(request.Email);
        if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(request.Senha))
            throw new RegraNegocioException("Informe e-mail e senha.");
        if (!Usuario.EmailValido(email) || request.Senha.Length > 256)
            throw new AcessoNegadoException("E-mail ou senha incorretos.");

        var usuario = await _usuarios.ObterPorEmailAsync(email);

        if (usuario is null)
        {
            // Mesmo custo de uma senha errada: o tempo de resposta não revela quais e-mails existem
            _hasher.Verificar(request.Senha, HashFicticio());
            await _usuarios.RegistrarTentativaLoginAsync(email, false, ip, "E-mail não cadastrado");
            throw new AcessoNegadoException("E-mail ou senha incorretos.");
        }

        // Conta bloqueada: nem confere a senha (impede continuar testando senhas)
        if (usuario.Bloqueado)
        {
            await _usuarios.RegistrarTentativaLoginAsync(email, false, ip, "Conta bloqueada");
            throw new ContaBloqueadaException(usuario.BloqueadoAte!.Value);
        }

        // Mensagem única para e-mail inexistente ou senha errada (não revela quais e-mails existem)
        if (!usuario.Ativo || !_hasher.Verificar(request.Senha, usuario.SenhaHash))
        {
            var bloqueadoAte = await _usuarios.RegistrarTentativaLoginAsync(email, false, ip,
                usuario.Ativo ? "Senha incorreta" : "Conta desativada");
            if (bloqueadoAte.HasValue) throw new ContaBloqueadaException(bloqueadoAte.Value);
            throw new AcessoNegadoException("E-mail ou senha incorretos.");
        }

        await _usuarios.RegistrarTentativaLoginAsync(email, true, ip, "Login");

        // Hash antigo (custo menor que o atual): refaz agora, aproveitando a senha correta em mãos
        if (_hasher.PrecisaAtualizar(usuario.SenhaHash))
            await _usuarios.AtualizarHashAsync(usuario.Id, _hasher.GerarHash(request.Senha));

        var (token, expiraEm) = _tokens.Gerar(usuario);
        return new LoginResponse(token, expiraEm, ParaResponse(usuario));
    }

    /// <summary>
    /// Troca a senha do usuário logado (exige a senha atual). As sessões abertas em outros
    /// aparelhos são encerradas; esta recebe um token novo para continuar logada.
    /// </summary>
    public async Task<LoginResponse> TrocarSenhaAsync(int usuarioId, TrocarSenhaRequest request)
    {
        var usuario = await _usuarios.ObterPorIdAsync(usuarioId)
                      ?? throw new RecursoNaoEncontradoException("Usuário não encontrado.");

        if (string.IsNullOrEmpty(request.SenhaAtual) || !_hasher.Verificar(request.SenhaAtual, usuario.SenhaHash))
            throw new RegraNegocioException("A senha atual não confere.");

        Usuario.ValidarForcaSenha(request.NovaSenha, usuario.Email);
        if (request.NovaSenha == request.SenhaAtual)
            throw new RegraNegocioException("A nova senha deve ser diferente da atual.");

        var versao = await _usuarios.AtualizarSenhaAsync(usuarioId, _hasher.GerarHash(request.NovaSenha));
        usuario.AtualizarVersaoToken(versao);
        var (token, expiraEm) = _tokens.Gerar(usuario);
        return new LoginResponse(token, expiraEm, ParaResponse(usuario));
    }

    /// <summary>"Sair de todos os aparelhos": invalida todos os tokens já emitidos para a conta.</summary>
    public Task SairDeTodosAsync(int usuarioId) => _usuarios.RevogarSessoesAsync(usuarioId);

    public async Task<UsuarioResponse> CadastrarAsync(CadastroRequest request)
    {
        if (!request.AceiteLgpd)
            throw new RegraNegocioException("É preciso aceitar a Política de Privacidade para criar a conta.");

        Usuario.ValidarForcaSenha(request.Senha, request.Email);
        var usuario = Usuario.NovoCliente(request.Nome, request.Email, _hasher.GerarHash(request.Senha));

        if (await _usuarios.EmailExisteAsync(usuario.Email))
            throw new RegraNegocioException("Este e-mail já está cadastrado.");

        usuario.Id = await _usuarios.InserirAsync(usuario);
        return ParaResponse(usuario);
    }

    public async Task<UsuarioResponse> ObterPerfilAsync(int usuarioId)
    {
        var usuario = await _usuarios.ObterPorIdAsync(usuarioId)
                      ?? throw new RecursoNaoEncontradoException("Usuário não encontrado.");
        return ParaResponse(usuario);
    }

    private static string? _hashFicticio;

    /// <summary>Hash de uma senha aleatória, gerado uma vez com o mesmo custo dos hashes reais.</summary>
    private string HashFicticio() =>
        _hashFicticio ??= _hasher.GerarHash(Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(18)));

    private static UsuarioResponse ParaResponse(Usuario u) =>
        new(u.Id, u.Nome, u.Email, u.Perfil.ToString());
}
