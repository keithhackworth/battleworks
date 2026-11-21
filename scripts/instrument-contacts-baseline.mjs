// Keep the pinned solver intact for timings. Add equivalent counters only to
// the second copy, which also supplies the original penetration measurement.
export function instrumentContactsBaseline(source) {
  function before(marker, code, count = 1) {
    const occurrences = source.split(marker).length - 1;
    if (occurrences !== count) throw new Error(`Pinned solver changed near ${marker}`);
    source = source.replaceAll(marker, code + marker);
  }
  before('local C={', 'local metrics\n');
  before('local p=b.plane; local gap=', 'if metrics then metrics.narrowTests+=1 end\n  ');
  before('local p=b.plane; local s=a.state;', 'if metrics then metrics.narrowTests+=1 end\n  ');
  source = source.replaceAll('if b.polygon then\n', 'if b.polygon then\n  if metrics then metrics.narrowTests+=1 end\n');
  source = source.replace('if metrics then metrics.narrowTests+=1 end\n  for _,p in r.polygon', 'for _,p in r.polygon');
  const axes = 'for _,axis in {{ax,az},{bx,bz},{cx,cz},{dx,dz}}';
  before(axes, 'if metrics then metrics.boxSatTests+=1;metrics.narrowTests+=1 end\n ', 2);
  before('for i,a in bodies do\n  for j=i+1', 'if metrics then metrics.pairVisits+=(#bodies*(#bodies-1)/2+#bodies*#statics) end\n ');
  source = source.replace('if found then table.insert(contacts,found) end',
    'if found then table.insert(contacts,found);if metrics then metrics.contacts+=#found end end');
  before('eachPair(bodies,statics,function(a,b)\n   local nx', 'if metrics then metrics.correctionPasses+=1 end\n  ');
  source = source.replace('function C.solve(bodies,statics,dt)', `function C.solve(bodies,statics,dt,stats)
 metrics=stats
 if stats then stats.candidateChecks=0;stats.pairVisits=0;stats.narrowTests=0;stats.boxSatTests=0;stats.contacts=0;stats.correctionPasses=0 end`);
  before('return C\n', `function C.penetration(a,b)
 local _,_,depth=separating(a,b)
 return depth or 0
end
`);
  source = source.replace('for _,r in bodies do Motion.sync(r.state) end', 'for _,r in bodies do Motion.sync(r.state) end\n metrics=nil');
  return source;
}
