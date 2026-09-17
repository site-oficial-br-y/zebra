/* Confere as coordenadas das formações. Rodar: node teste-formacoes.js
   Pega o defeito que o desenho tem quando duas posições espelhadas ficam
   em alturas diferentes — o campo lê como torto. */
const fs = require('fs');
const src = fs.readFileSync(__dirname + '/tmpl.html', 'utf8');
const bloco = src.slice(src.indexOf('const FORMACOES'), src.indexOf('const ESTILOS'));
const P = (g, rot, x, y) => ({g, rot, x, y});
const FORMACOES = eval(bloco.replace('const FORMACOES =', '').replace(/;\s*$/, ''));

let falhas = 0;
const erro = m => { console.log('  FALHA ' + m); falhas++; };

for (const f of FORMACOES) {
  if (f.pos.length !== 11) erro(`${f.n}: ${f.pos.length} jogadores`);

  const n = {GOL:0, DEF:0, MEI:0, ATA:0};
  f.pos.forEach(p => n[p.g]++);
  if (n.GOL !== 1 || n.DEF !== f.d || n.MEI !== f.m || n.ATA !== f.a)
    erro(`${f.n}: setores ${JSON.stringify(n)} não batem com ${f.d}-${f.m}-${f.a}`);

  const chaves = f.pos.map(p => p.x + ',' + p.y);
  if (new Set(chaves).size !== chaves.length) erro(`${f.n}: duas posições no mesmo ponto`);

  for (const p of f.pos) {
    if (p.x < 8 || p.x > 92) erro(`${f.n}: ${p.rot} sai pela lateral (x=${p.x})`);
    if (p.y < 10 || p.y > 94) erro(`${f.n}: ${p.rot} sai pela linha de fundo (y=${p.y})`);
  }

  // o que deixa o campo torto: mesmo setor, posição espelhada, alturas diferentes
  for (const a of f.pos) for (const b of f.pos) {
    if (a === b || a.g !== b.g || a.x >= b.x) continue;
    if (Math.abs((100 - a.x) - b.x) <= 3 && a.y !== b.y)
      erro(`${f.n} ${a.g}: ${a.rot}(y${a.y}) e ${b.rot}(y${b.y}) espelhados em alturas diferentes`);
  }

  // o goleiro é o mais recuado, e os atacantes os mais adiantados
  const gol = f.pos.find(p => p.g === 'GOL');
  if (f.pos.some(p => p.g !== 'GOL' && p.y >= gol.y)) erro(`${f.n}: alguém atrás do goleiro`);
  const maisFundo = Math.min(...f.pos.filter(p => p.g === 'ATA').map(p => p.y));
  if (f.pos.some(p => p.g !== 'ATA' && p.y < maisFundo)) erro(`${f.n}: alguém à frente dos atacantes`);
}

console.log(falhas ? `\n${falhas} problema(s)` : `${FORMACOES.length} formações, tudo certo`);
process.exit(falhas ? 1 : 0);
