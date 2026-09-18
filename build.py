#!/usr/bin/env python3
"""Monta o index.html a partir da casca, da lógica e das duas bases."""
import io, json, os

def ler(p): return io.open(p, encoding='utf-8').read()

casca = ler('casca.html')
logica = ler('js.txt')
assert casca.count('__JS__') == 1, 'casca.html precisa de um __JS__'
io.open('tmpl.html', 'w', encoding='utf-8').write(casca.replace('__JS__', logica))

hist = json.load(open('elencos.json', encoding='utf-8'))
hist.pop('_leia', None)
dados = {
    'times':  hist['times'] if isinstance(hist, dict) else hist,   # lendas
    'atuais': json.load(open('elencos-2026.json', encoding='utf-8')),
    'sul':    json.load(open('elencos-sul.json', encoding='utf-8')),   # Libertadores
    'europa': json.load(open('elencos-europa.json', encoding='utf-8')),  # Mundial
}
for nome, base in dados.items():
    for t in base:
        assert len(t['elenco']) == 11, (nome, t['clube'])
        g = [j['grupo'] for j in t['elenco']]
        assert g.count('GOL') == 1, (nome, t['clube'], 'precisa de um goleiro')

tmpl = ler('tmpl.html')
assert tmpl.count('__DADOS__') == 1
io.open('index.html', 'w', encoding='utf-8').write(
    tmpl.replace('__DADOS__', json.dumps(dados, ensure_ascii=False, separators=(',', ':'))))

print('%d elencos históricos, %d atuais, %d sul-americanos, %d europeus · index.html com %d KB' % (
    len(dados['times']), len(dados['atuais']), len(dados['sul']), len(dados['europa']),
    os.path.getsize('index.html') / 1024))
