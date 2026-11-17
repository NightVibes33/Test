/**
 * iOS-compatible implementation of @ff-labs/fff-node's FileFinder operations.
 * Replaces only native filesystem search. Results come from the real user workspace.
 * This module deliberately avoids ffi-rs, .node add-ons, and spawning commands.
 */
import fs from 'node:fs';
import path from 'node:path';

const OK = value => ({ok:true, value});
const ERROR = err => ({ok:false, error:String(err?.message || err)});
const IGNORE = new Set(['.git', 'node_modules', '.build', 'build', 'DerivedData', '.next', 'dist']);
const norm = x => x.replaceAll(path.sep, '/');
function fuzzy(haystack, query) {
  if (!query) return 1;
  const h=haystack.toLowerCase(), q=query.toLowerCase();
  if (h.includes(q)) return 10000 - h.indexOf(q) - (h.length - q.length);
  let at=0, score=0;
  for(const c of q) {const i=h.indexOf(c,at); if(i<0) return -1; score+=i===at ? 7:1; at=i+1;}
  return score;
}
function scan(base, limit=160000) {
  const files=[], directories=[{relativePath:''}], stack=[['',0]];
  while(stack.length && files.length+directories.length<limit) {
    const [relative,depth]=stack.pop();
    if(depth>20) continue;
    let entries;
    try { entries=fs.readdirSync(path.join(base,relative),{withFileTypes:true}); } catch { continue; }
    for(const entry of entries) {
      if(entry.isSymbolicLink()) continue;
      const rel=norm(path.join(relative,entry.name));
      if(entry.isDirectory()) {
        if(IGNORE.has(entry.name)) continue;
        directories.push({relativePath:rel}); stack.push([rel,depth+1]);
      } else if(entry.isFile()) {
        files.push({relativePath:rel});
      }
      if(files.length+directories.length>=limit) break;
    }
  }
  return {files,directories};
}
function page(items,opts={}) {
  const size=Math.min(Math.max(1,opts.pageSize||100),10000);
  const start=(opts.pageIndex||0)*size;
  return {items:items.slice(start,start+size),totalMatched:items.length};
}
function globToRegExp(pattern) {
  let source='^';
  for(let i=0;i<pattern.length;i++) {
    const c=pattern[i];
    if(c==='*') {if(pattern[i+1]==='*') {i++; if(pattern[i+1]==='/'){i++;source+='(?:.*/)?';} else source+='.*'; } else source+='[^/]*';}
    else if(c==='?') source+='[^/]';
    else source+=/[.\\+^$(){}|\[\]]/.test(c)?'\\'+c:c;
  }
  return new RegExp(source+'$');
}
export class FileFinder {
  constructor(base) {this.base=base;this.isDestroyed=false;this.index=scan(base);}
  static create(opts) {try {if(!fs.statSync(opts.basePath).isDirectory())throw Error('Not a folder');return OK(new FileFinder(opts.basePath));}catch(e){return ERROR(e);}}
  destroy(){this.isDestroyed=true;this.index={files:[],directories:[]};}
  ensure(){return this.isDestroyed?ERROR('FileFinder destroyed'):OK(true);}
  async waitForIndexReady(){return this.isDestroyed?ERROR('FileFinder destroyed'):OK(true);}
  async waitForScan(){return this.waitForIndexReady();}
  isScanning(){return false;}
  scanFiles(){if(this.isDestroyed)return this.ensure();this.index=scan(this.base);return OK(true);}
  _search(query,opts,type){
    if(this.isDestroyed)return this.ensure();
    const source=type==='file'?this.index.files:type==='directory'?this.index.directories:[...this.index.files.map(item=>({type:'file',item})),...this.index.directories.map(item=>({type:'directory',item}))];
    const ranked=source.map(x=>({x,score:fuzzy(type==='mixed'?x.item.relativePath:x.relativePath,query)})).filter(x=>x.score>=0).sort((a,b)=>b.score-a.score || JSON.stringify(a.x).localeCompare(JSON.stringify(b.x))).map(x=>x.x);
    return OK(page(ranked,opts));
  }
  fileSearch(q,opts){return this._search(q,opts,'file');}
  directorySearch(q,opts){return this._search(q,opts,'directory');}
  mixedSearch(q,opts){return this._search(q,opts,'mixed');}
  glob(q,opts){try {const re=globToRegExp(q);return OK(page(this.index.files.filter(x=>re.test(x.relativePath)),opts));}catch(e){return ERROR(e);}}
  grep(q,opts={}) {
    if(this.isDestroyed)return this.ensure();
    const pageSize=Math.min(Math.max(1,opts.pageSize||100),10000);
    const offset=opts.cursor?._offset||0;const matches=[];
    let re=null;
    if(opts.mode==='regex'){try {re=new RegExp(q,'g'+(opts.smartCase?'i':''));}catch(e){return ERROR(e);}}
    else if(!q) return OK({items:[],nextCursor:null});
    const needle=opts.smartCase?q.toLowerCase():q;
    for(const file of this.index.files) {
       const filepath=path.join(this.base,file.relativePath);
      try{
        const stat=fs.statSync(filepath); if(stat.size>(opts.maxFileSize||2_000_000))continue;
        const body=fs.readFileSync(filepath,'utf8'); if(body.includes('\0'))continue;
        const lines=body.split(/\r?\n/);
        let found=0;
        for(let i=0;i<lines.length;i++) {
          const line=lines[i], ranges=[];
          if(re) {re.lastIndex=0;let m;while((m=re.exec(line)) && ranges.length<30){if(!m[0])break;ranges.push([Buffer.byteLength(line.slice(0,m.index)),Buffer.byteLength(line.slice(0,m.index+m[0].length))]);}}
          else{const hay=opts.smartCase?line.toLowerCase():line; let from=0,pos;while((pos=hay.indexOf(needle,from))>=0 && ranges.length<30){yranges.push([Buffer.byteLength(line.slice(0,pos)),Buffer.byteLength(line.slice(0,pos+needle.length))]);from=pos+Math.max(1,needle.length);}}
          if(ranges.length){matches.push({relativePath:file.relativePath,lineNumber:i+1,lineContent:line,matchRanges:ranges});found++;}
          if(found>=(opts.maxMatchesPerFile||100)) break;
        }catch{}
      if(matches.length>=offset+pageSize+1) break;
    }
    return OK({items:matches.slice(offset,offset+pageSize),nextCursor:matches.length>offset+pageSize?{_offset:offset+pageSize}:null});
  }
}
