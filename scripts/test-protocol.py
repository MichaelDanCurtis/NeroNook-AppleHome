#!/usr/bin/env python3
"""Runs a separately ad-hoc-signed, unentitled protocol fixture only.
Never initializes HMHomeManager or requests Home access. This proves Catalyst IPC,
not HomeKit permission, provisioning, inventory or the signed release.
"""
import json,os,pathlib,selectors,subprocess,time,uuid,sys
cards_mode="--cards" in sys.argv
root=pathlib.Path(__file__).resolve().parents[1]
source=root/'build/SignedDerivedData/Build/Products/Release-maccatalyst/Apple Home Module.app'
fixture=root/'build/ProtocolFixture.app'
subprocess.run(['/usr/bin/ditto',str(source),str(fixture)],check=True)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(fixture)],check=True,capture_output=True)
p=subprocess.Popen([str(fixture/'Contents/MacOS/Apple Home Module'),'--neronook-plugin','--protocol-test'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
session=str(uuid.uuid4());plugin='cafe.nero.plugin.applehome';buffer=b'';last=-1
selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
def send(kind,**kwargs):
 p.stdin.write((json.dumps(dict(apiVersion=1,type=kind,pluginID=plugin,session=session,sequence=0,**kwargs))+'\n').encode());p.stdin.flush()
def wait_for(predicate):
 global buffer,last
 end=time.monotonic()+15
 while time.monotonic()<end:
  if b'\n' not in buffer:
   if not selector.select(1):continue
   data=os.read(p.stdout.fileno(),131072)
   if not data:raise AssertionError('Catalyst fixture exited: '+p.stderr.read().decode(errors='replace')[-1200:])
   buffer+=data
  while b'\n' in buffer:
   line,buffer=buffer.split(b'\n',1);m=json.loads(line)
   assert len(line)<131072 and m['sequence']>last;last=m['sequence']
   assert m['pluginID']==plugin and m['session'].lower()==session.lower()
   if predicate(m):return m
 raise AssertionError('Catalyst response deadline')
try:
 send('hello',features=['actions-v1','dashboard-v1','panels-v1','diagrams-v1']+(['control-cards-v1'] if cards_mode else []))
 ready=wait_for(lambda m:m['type']=='ready');assert 'actions-v1' in ready['features']
 snap=wait_for(lambda m:m['type']=='snapshot')['snapshot']
 assert [p['title'] for p in snap['panels']]==['Favorites','Rooms','Scenes'] and len(snap['activity'])<=100
 for panel in snap['panels']:
  if cards_mode: assert panel['cards']==[] and 'diagrams' not in panel
  else:
   d=panel['diagrams'][0];assert d['width']/d['height']==16/9
   for e in d['elements']:assert 0<=e['x']+e['w']<=d['width'] and 0<=e['y']+e['h']<=d['height']
 request=str(uuid.uuid4());send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='read_status')))
 result=wait_for(lambda m:m['type']=='bus' and m.get('bus',{}).get('requestID','').lower()==request.lower())
 assert result['bus']['update']['phase']=='succeeded' and result['bus']['update']['values']['connected']==False
 wait_for(lambda m:m['type']=='snapshot')
 print('PASS: real Catalyst launch/stdio, handshake, timed snapshots, 16:9 content panels and read-only SDK status. HomeKit not accessed.')
finally:
 selector.close();p.stdin.close()
 try:p.wait(timeout=5)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
