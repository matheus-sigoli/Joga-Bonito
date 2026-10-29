// ============================================================================
// JOGA BONITO — configuração do front-end por ambiente (config.js)
//
// apiBase = null  → detecção automática (recomendado):
//   * site servido pela própria API (local na porta 5000 ou publicado no Azure):
//     usa caminhos relativos ("/api/..."), ou seja, a MESMA origem do site;
//   * site aberto por Live Server/arquivo no próprio computador: usa http://localhost:5000.
//
// apiBase = "https://endereco-da-api"  → quando o site for hospedado em um lugar
//   e a API em outro (lembre de liberar a origem do site em Cors__Origens na API).
// ============================================================================
window.JB_CONFIG = {
  apiBase: null
};
