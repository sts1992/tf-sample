// Original demonstration UI; intentionally distinct from the AWS workshop app.
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
function App() {
  const [result, setResult] = useState(null);
  const [busy, setBusy] = useState(false);
  async function check(path) {
    setBusy(true);
    try {
      const response = await fetch(path, { signal: AbortSignal.timeout(15000) });
      const data = await response.json();
      setResult({ http_status: response.status, ...data });
    } catch (error) {
      setResult({ ok: false, error: error.message });
    } finally { setBusy(false); }
  }
  return <main>
    <p className="label">THEME A · INDEPENDENT DEMO</p>
    <h1>Web 3 層システム</h1>
    <p>Nginx / React → 内部 ALB → Node.js → Aurora MySQL</p>
    <p>ボタンを押すと実際の DB に読み取りクエリを実行します。AWS 公式ワークショップのアプリではありません。</p>
    <div><button disabled={busy} onClick={() => check('/api/health')}>Writer 接続を確認</button>
    <button disabled={busy} onClick={() => check('/api/reader')}>Reader 接続を確認</button></div>
    {busy && <p>接続中…</p>}
    {result && <pre>{JSON.stringify(result, null, 2)}</pre>}
    <footer>学習用・個人情報や機密情報を入力しないでください。</footer>
  </main>;
}
createRoot(document.getElementById('root')).render(<App />);
