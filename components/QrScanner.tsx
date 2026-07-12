"use client";
import { useEffect, useId } from "react";
import { Html5QrcodeScanner } from "html5-qrcode";

export default function QrScanner({ onScan }: { onScan: (value: string) => void }) {
  const id = `qr-${useId().replace(/:/g, "")}`;
  useEffect(() => {
    const scanner = new Html5QrcodeScanner(id, { fps: 10, qrbox: { width: 240, height: 240 } }, false);
    scanner.render((text) => { onScan(text); scanner.clear().catch(() => undefined); }, () => undefined);
    return () => { scanner.clear().catch(() => undefined); };
  }, [id, onScan]);
  return <div className="qr-wrap" id={id} />;
}
