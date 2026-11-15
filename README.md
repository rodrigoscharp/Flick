# Flick

Manda fotos, vídeos e arquivos do iPhone para o Mac arrastando para o lado. O arquivo chega no Mac com uma animação embaixo do notch.

## Como funciona

- **Mac:** app de barra de menus em Swift. Sobe um servidor na rede local (porta 8787), salva o que chega em `~/Flick` e mostra a animação de chegada.
- **AirDrop:** o Flick observa `~/Downloads`. Quando chega um arquivo por AirDrop, ele mostra a mesma animação. Funciona sem roteador, porque o AirDrop conecta o iPhone direto ao Mac.
- **iPhone:** página web servida pelo próprio Mac. Abre no Safari e pode ir para a Tela de Início como app. Sem Xcode e sem conta de desenvolvedor.

## Animação de chegada

Uma aura colorida acende colada na borda direita da tela. A foto sai de dentro dela, faz uma curva até o notch e vira uma ilha preta, no estilo Dynamic Island. Clicar na ilha mostra o arquivo no Finder.

## Rodar

Precisa das Command Line Tools da Apple (`xcode-select --install`).

```bash
cd ~/Dev/Flick
swift run -c release
```

1. Aparece um ícone de avião de papel na barra de menus e uma janela com QR code.
2. Com o iPhone no mesmo Wi-Fi, aponte a câmera para o QR code.
3. No Safari: Compartilhar > Adicionar à Tela de Início.
4. Escolha os arquivos e arraste o cartão para o lado, ou toque em **Enviar**.

O QR code usa o nome Bonjour do Mac (`nome-do-mac.local`), então o atalho da Tela de Início continua funcionando quando o IP muda.

Menu do ícone: reconectar iPhone, abrir a pasta de recebidos, testar a animação, sair.

## Limites desta versão

- A página web só funciona com iPhone e Mac na mesma rede, e o roteador precisa deixar os aparelhos se enxergarem (sem isolamento de clientes). O AirDrop não tem essa limitação.
- Sem senha nem criptografia: qualquer aparelho na mesma rede consegue enviar arquivos para o Mac enquanto o app está aberto.
- O gesto funciona dentro da página, não no sistema inteiro do iPhone.

## Próximos passos

- Atalho do iOS para enviar direto do menu Compartilhar.
- App nativo de iPhone (exige Xcode completo).
- Código de pareamento e empacotar como `.app` com início automático.
