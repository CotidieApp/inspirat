import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Consola local de pruebas | inspíraT",
  description:
    "Interfaz local para probar usuarios, cuentos y mensajes de inspíraT.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
