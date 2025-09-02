# Sauron


# Sauron — Stego Tool for PDF

Ferramenta simples para extrair **streams** de PDFs e identificar possíveis conteúdos **JavaScript** nos CTFS da FIAP.

---

## Compilação
Use o Makefile incluso:
```bash
make
```
Isso detecta automaticamente macOS ou Linux e gera o binário `sauron`.

Para limpar:
```bash
make clean
```

---

## Uso
```bash
./sauron arquivo.pdf
```

Saída esperada:
```
[+] Valid PDF
[+] Stream 000 | filters: FlateDecode | 1024 → 4389 bytes | saved: stream_000.js
[dump 0]
function launch(){ ... }
```

Streams são salvos no diretório atual como `.js`, `.txt` ou `.bin`.

---

## Limitações
- Não resolve `/Length` indireto.
- Não suporta filtros menos comuns.
- Detecção de JS é heurística simples.

---

## Notas 
- Fiz isso pra minha turma em especifico, não vou fazer updates
- É mais fácil usar qualquer pacote de python que faça isso
- Fé nas crianças

## Autor
- **Sauron — Stego Tool for PDF**
- Criado por **Oozaru**  
- GitHub: https://github.com/oozaru-re

