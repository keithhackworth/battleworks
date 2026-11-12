#!/usr/bin/env node
'use strict';
const path=require('node:path');const {Store}=require('./world-builder/store');const {createServer}=require('./world-builder/server');
async function main(){const store=new Store(path.resolve(__dirname,'..'));await store.init();await store.rebuild();if(process.argv.includes('--build')){console.log('World builder: generated templates and all world registrations.');return;}
 const args=process.argv.slice(2);if(args.some(a=>!['--build','--studio'].includes(a)))throw new Error('Usage: node tools/world-builder.js [--build | --studio]');
 let rojo;if(args.includes('--studio')){rojo=require('node:child_process').spawn('rojo',['serve'],{cwd:path.resolve(__dirname,'..'),stdio:'inherit'});rojo.on('error',e=>console.error('Rojo: '+e.message));process.on('exit',()=>rojo.kill());}
 const port=Number(process.env.BW_BUILDER_PORT||34873);if(!Number.isInteger(port)||port<1024||port>65535)throw new Error('Invalid BW_BUILDER_PORT');const server=createServer(store);server.on('error',e=>{console.error(e.message);process.exitCode=1;});server.listen(port,'127.0.0.1',()=>console.log(`BattleWorks world builder bridge: http://127.0.0.1:${port}\nLeave this running while editing. Connect from the Studio plugin.`));}
main().catch(e=>{console.error(`World builder: ${e.message}`);process.exitCode=1;});
