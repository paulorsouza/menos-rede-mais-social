// A versão "light" do hls.js tem a mesma API da completa, só sem legendas
// embutidas no HLS, áudio alternativo e DRM, que a rede não usa.
declare module 'hls.js/light' {
  export { default } from 'hls.js'
  export * from 'hls.js'
}
