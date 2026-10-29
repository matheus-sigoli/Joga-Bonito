# ADR 003 — App Flutter testado em celular Android real

**Data:** 27/10/2026 · **Situação:** aceita

## Contexto
O Flutter não estava instalado no PC. Emulador exige o Android Studio (~3 GB a mais).
O app escolhe a API por `--dart-define=API_URL` (padrão `http://10.0.2.2:5000`, que só existe
no emulador) ou por *Perfil › Servidor da API*.

## Decisão
Instalar o Flutter e o Android SDK de linha de comando, sem Android Studio, e testar num
celular Android real na mesma rede Wi-Fi do PC.

## Instalação feita em 27/10/2026
Flutter 3.47.8 em `C:\flutter`, Android SDK em `C:\Android` (licenças aceitas), ambos no PATH do
usuário, com `ANDROID_HOME=C:\Android`. Funciona com o JDK 25 já instalado. `flutter analyze` sem
avisos (4 APIs obsoletas trocadas), 15 testes OK, `flutter build apk --debug` OK. O primeiro build
leva ~25 min (download do Gradle); os seguintes são rápidos. Passo a passo do celular:
`Maestro/docs/qa/roteiros-manuais.md`, roteiro 5.

## Consequências
- A loja sobe com `iniciar-projeto.bat -Rede` (aceita conexões da rede local) e o app aponta
  para `http://IP-DO-PC:5000`.
- O celular precisa da **depuração USB** (ou depuração sem fio) ativada, e o app roda com
  `flutter run`: só a build de depuração aceita HTTP (o `tool/preparar_android.dart` libera
  HTTP apenas nela).
- O APK de produção (`flutter build apk --release`) só serve quando houver loja com HTTPS
  ([ADR 002](002-implantacao-azure-adiada.md)).
- Validação da integração: uma compra pelo app precisa aparecer com origem **Mobile** no
  mesmo histórico de pedidos do site.
