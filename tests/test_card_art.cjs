const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const A=require('../chapter/card_art.js');
const F=require('../chapter/model.js');
const C=require('../chapter/catalog.js');
const manifest=require('../assets/generated/card-art.json');
const root=path.resolve(__dirname,'..');

test('chapter and Godot share the declared owner/move manifest and identical source art',()=>{
 assert.deepEqual(A.actors,manifest.actors);
 for(const [actor,spec] of Object.entries(A.actors)){
  const source=fs.readFileSync(path.join(root,spec.path.replace('res://','')));
  const copy=fs.readFileSync(path.join(root,'chapter/assets',path.basename(spec.path)));
  assert.equal(crypto.createHash('sha256').update(source).digest('hex'),crypto.createHash('sha256').update(copy).digest('hex'));
  assert.equal(source.readUInt32BE(16),spec.width);assert.equal(source.readUInt32BE(20),spec.height);
  spec.cards.forEach((card,index)=>{
   const value=A.resolve(actor,card);assert.equal(value.actor,actor);assert.equal(value.index,index);
   const [x,y,w,h]=value.viewBox.split(' ').map(Number);
   assert(x>=0&&y>=0&&x+w<=spec.width&&y+h<=spec.height);
  });
 }
});
test('all currently learned hero and first-companion moves have their own artwork',()=>{
 const state=F.Game.fresh().s;
 for(const actor of ['hero','huai']){
  for(const card of new Set([...state.actors[actor].deck,...state.actors[actor].learned]))assert(A.resolve(actor,card),`${actor}/${card}`);
 }
 assert.equal(A.actors.hero.cards.length,12);assert.equal(A.actors.huai.cards.length,7);
});
test('same technique selects different people without changing rules or saves',()=>{
 const state=F.Game.fresh().s,before=JSON.stringify(state),catalog=JSON.stringify(C);
 for(const card of A.actors.huai.cards){assert.notEqual(A.resolve('hero',card).url,A.resolve('huai',card).url);}
 assert.equal(JSON.stringify(state),before);assert.equal(JSON.stringify(C),catalog);
});
test('unpainted characters and unknown techniques remain neutral, never borrowing the hero',()=>{
 for(const card of F.Game.fresh().s.actors.du.learned)assert.equal(A.resolve('du',card),null);
 assert.equal(A.resolve('huai','hidden_needle'),null);
 assert.equal(A.resolve('hero','unknown'),null);
 assert.equal(A.resolve('__proto__','strike'),null);
});
