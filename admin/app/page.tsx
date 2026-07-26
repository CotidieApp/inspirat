import type { Metadata } from "next";
import { TesterConsole } from "./tester-console";

export const metadata: Metadata = {
  title: "Consola local de pruebas | inspíraT",
  description:
    "Herramienta local para probar la comunidad de inspíraT con varias personas.",
};

export default function Home() {
  return <TesterConsole />;
}
