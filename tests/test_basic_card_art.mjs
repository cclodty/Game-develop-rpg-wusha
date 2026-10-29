import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,statSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {CARDS,ACTORS} from '../battle/catalog.mjs';
const root=new URL('../',import.meta.url);
const read=path=>readFileSync(new URL(path,root));
const manifest=JSON.parse(read('assets/cards/basic/manifest.json'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');

test('18 actor/technique files, unique single-image originals and no atlas coordinates',()=>{
 assert.equal(manifest.images.length,18);assert.equal(new Set(manifest.images.map(x=>x.sha256)).size,18);
 for(const actor of Object.keys(ACTORS))for(const card of Object.keys(CARDS)){
  const record=manifest.images.find(x=>x.actor===actor&&x.card===card);assert(record);
  assert.equal(record.url,`assets/cards/basic/${actor}/${card}.webp`);assert(record.reviewed);assert(record.review);
  assert(!Object.hasOwn(record,'viewBox'));assert(!record.url.includes('atlas'));
 }
});
test('all PNG originals are 1536x1024; runtime WebP hashes and sizes are exact',()=>{
 for(const record of manifest.images){
  const png=read(record.original),webp=read(record.url);
  assert.equal(png.readUInt32BE(16),1536);assert.equal(png.readUInt32BE(20),1024);
  assert.equal(sha(png),record.source_sha256);assert.equal(sha(webp),record.sha256);
  assert.equal(webp.toString('ascii',0,4),'RIFF');assert.equal(webp.toString('ascii',8,12),'WEBP');
  assert.equal(webp.length,record.bytes);assert(record.bytes<200000);
 }
});
test('complete compressed card collection remains under three megabytes',()=>{
 const actual=manifest.images.reduce((n,r)=>n+statSync(new URL(r.url,root)).size,0);
 assert.equal(actual,manifest.total_web_bytes);assert(actual<3000000);
});
