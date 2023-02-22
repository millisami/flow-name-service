import { Html, Head, Main, NextScript } from 'next/document'

export default function Document() {
  return (
    <Html lang="en" data-theme="dark">
      <Head />
      <body>
        <main className='container'>
          <Main />
          <NextScript />
        </main>
      </body>
    </Html>
  )
}
