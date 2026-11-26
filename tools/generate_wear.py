#!/usr/bin/env python3
import argparse, json, math, random, subprocess, tempfile
from pathlib import Path

# weight, relative width range, opacity range
PROFILES = {
    'silver': (55, .05, .25, .4, 1),
    'brown': (15, .08, .25, .15, .5),
    'yellow': (20, .03, .12, .4, .9),
    'rust': (10, .03, .15, .5, 1),
    'dents': (10, .01, .05, .6, 1),
    'fine_scratches': (35, .05, .25, .4, .9),
    'deep_scratches': (15, .05, .20, .7, 1),
    'gouges': (5, .03, .15, .7, 1),
    'scuffs': (10, .05, .15, .15, .4),
    'grime': (5, .05, .20, .10, .35),
    'corrosion': (10, .02, .10, .6, 1),
    'paint_transfer': (10, .02, .10, .4, .9),
    'adhesive_residue': (2, .05, .15, .1, .25),
}
DEFAULT = (10, .03, .15, .3, .8)
#LIMITS = dict(fine_scratches=40, deep_scratches=10, gouges=4, dents=5,
              #scuffs=10, grime=10, corrosion=12, paint_transfer=10,
              #adhesive_residue=1)
LIMITS = dict(scuffs=2, grime=2, deep_scratches=1, dents=1)


def run(*args):
    subprocess.run([str(x) for x in args], check=True)

def dimensions(path):
    return tuple(map(int, subprocess.check_output(['identify','-format','%w %h',str(path)], text=True).split()))

def fade_surface(base, out, mask, w, h, strength, scale, seed, tmp, saturation, brightness):
    # Smooth, seeded low-frequency noise. White means more fading.
    patch = max(2, min(w,h)*scale)
    nw, nh = max(2, math.ceil(w/patch)), max(2, math.ceil(h/patch))
    noise = tmp/'fade_noise.miff'
    run('convert','-seed',seed,'-size',f'{nw}x{nh}','xc:gray',
        '+noise','Random','-colorspace','gray','-filter','Mitchell',
        '-resize',f'{w}x{h}!','-blur',f'0x{max(1,patch*.12)}',
        '-level','20%,85%','-evaluate','multiply',str(strength/100),
        '-alpha','copy',noise)
    # Modify the original colors rather than painting a white cloud over them.
    # Local brightness and saturation are independently configurable.
    run('convert',base,'-alpha','off','-modulate',f'{brightness},{saturation},100',
        noise,'-compose','CopyOpacity','-composite',
        mask,'-compose','DstIn','-composite',tmp/'fade_layer.miff')
    run('convert',base,tmp/'fade_layer.miff','-compose','Over','-composite',
        base,'-compose','CopyOpacity','-composite',out)

def main():
    p = argparse.ArgumentParser(description='Stamp randomized wear decals onto transparent UI artwork.')
    p.add_argument('--base', type=Path, required=True)
    p.add_argument('--decals', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('/tmp/wear-generated'))
    p.add_argument('--count', type=int, default=50)
    p.add_argument('--width', type=int, default=512)
    p.add_argument('--wear', type=float, default=60)
    p.add_argument('--min-stamps', type=int, default=8)
    p.add_argument('--max-stamps', type=int, default=20)
    p.add_argument('--inset', type=int, default=15, help='Inset in original source pixels')
    p.add_argument('--seed', type=int, default=42)
    p.add_argument('--fade', type=float, default=0, help='Maximum localized fading, 0–100')
    p.add_argument('--fade-scale', type=float, default=.25, help='Patch size relative to shorter image dimension')
    p.add_argument('--base-saturation', type=float, default=75)
    p.add_argument('--saturation-jitter', type=float, default=10)
    p.add_argument('--fade-saturation', type=float, default=40, help='Local saturation as percent of globally adjusted saturation')
    p.add_argument('--fade-brightness', type=float, default=105)
    p.add_argument('--profile', type=Path, help='JSON category overrides')
    a = p.parse_args()
    if not (0 <= a.fade <= 100 and .02 <= a.fade_scale <= 2):
        p.error('Fade must be 0–100 and fade-scale .02–2')
    if not (0 <= a.base_saturation <= 100 and 0 <= a.saturation_jitter <= 100 and 0 <= a.fade_saturation <= 100 and 0 <= a.fade_brightness <= 200):
        p.error('Invalid saturation or brightness')
    profiles = dict(PROFILES)
    limits = dict(LIMITS)
    placements = {'dents':'interior', 'adhesive_residue':'interior',
                  'rust':'edge', 'corrosion':'edge'}
    if a.profile:
        for cat, cfg in json.loads(a.profile.read_text()).items():
            weight, lo, hi, omin, omax = profiles.get(cat, DEFAULT)
            profiles[cat] = (cfg.get('weight',weight), *cfg.get('width',[lo,hi]),
                             *cfg.get('opacity',[omin,omax]))
            if 'max_count' in cfg: limits[cat] = cfg['max_count']
            if 'placement' in cfg: placements[cat] = cfg['placement']
    for cat, (weight,lo,hi,omin,omax) in profiles.items():
        if not (weight >= 0 and 0 < lo <= hi <= 1 and 0 <= omin <= omax <= 1):
            p.error(f'Invalid profile: {cat}')
        if limits.get(cat,200) < 0 or placements.get(cat,'anywhere') not in ('anywhere','edge','interior'):
            p.error(f'Invalid limit or placement: {cat}')
    if not (0 <= a.wear <= 100 and 0 <= a.min_stamps <= a.max_stamps and a.count > 0 and a.width > 0 and a.inset >= 0):
        p.error('Invalid count, width, wear, inset or stamp range')
    groups = {d.name: [f for f in sorted(d.rglob('*.png'))
                       if not any(part.startswith('_') for part in f.relative_to(d).parts)]
              for d in sorted(a.decals.iterdir()) if d.is_dir() and not d.name.startswith('_')}
    groups = {k:v for k,v in groups.items() if v}
    if not groups: p.error('No PNG decals found in category subdirectories')
    rng = random.Random(a.seed)
    fade_rng = random.Random(a.seed ^ 0xFADE)
    saturation_rng = random.Random(a.seed ^ 0x5A7)
    a.output.mkdir(parents=True, exist_ok=True)
    original_width, _ = dimensions(a.base)
    manifest = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp); base = tmp/'base.miff'; mask = tmp/'mask.miff'
        run('convert', a.base, '-alpha','set','-resize',f'{a.width}x',base)
        w,h = dimensions(base)
        inset = round(a.inset*w/original_width)
        cmd = ['convert',base,'-alpha','extract','-threshold','98%','-virtual-pixel','black']
        if inset: cmd += ['-morphology','Erode',f'Disk:{inset}']
        run(*cmd,'-alpha','copy',mask)
        # Read the actual allowed pixels so stamps land on the artwork.
        raw = subprocess.check_output(['convert',mask,'-alpha','extract','-depth','8','gray:-'])
        allowed = [(i%w,i//w) for i,v in enumerate(raw) if v>127]
        if not allowed: p.error('Inset mask is empty; reduce --inset')
        edge = [(x,y) for x,y in allowed if y<h*.25 or y>h*.75 or x<w*.12 or x>w*.88] or allowed
        names = list(groups)
        interior_mask = tmp/'interior.miff'
        margin = max(1, round(min(w,h)*.15))
        run('convert',mask,'-alpha','extract','-virtual-pixel','black',
            '-morphology','Erode',f'Disk:{margin}',interior_mask)
        iraw = subprocess.check_output(['convert',interior_mask,'-depth','8','gray:-'])
        interior = [(i%w,i//w) for i,v in enumerate(iraw) if v>127]
        inner_set = set(interior)
        edge = [pt for pt in allowed if pt not in inner_set] or allowed
        print('Categories:', ', '.join(f'{k}={len(v)}' for k,v in groups.items()))
        for i in range(1,a.count+1):
            saturation = max(0, min(100, a.base_saturation + saturation_rng.uniform(-a.saturation_jitter,a.saturation_jitter)))
            toned = tmp/'toned.miff'
            run('convert',base,'-modulate',f'100,{saturation},100',base,'-compose','CopyOpacity','-composite',toned)
            faded = toned
            fade_seed = None
            if a.fade:
                fade_seed = fade_rng.randrange(2**31)
                faded = tmp/'faded.miff'
                fade_surface(toned, faded, mask, w, h, a.fade, a.fade_scale, fade_seed, tmp, a.fade_saturation, a.fade_brightness)
            count = round(rng.randint(a.min_stamps,a.max_stamps)*a.wear/60)
            count = min(count, 200)
            layers = []; cmd = ['convert',base]
            used = {}
            for _ in range(count):
                eligible = [k for k in names if used.get(k,0)<limits.get(k,200)
                            and profiles.get(k,DEFAULT)[0]>0
                            and (placements.get(k)!='interior' or interior)]
                if not eligible: break
                cat = rng.choices(eligible,[profiles.get(k,DEFAULT)[0] for k in eligible])[0]
                src = rng.choice(groups[cat]); _,lo,hi,omin,omax = profiles.get(cat,DEFAULT)
                used[cat] = used.get(cat,0)+1
                size = max(1,round(w*rng.uniform(lo,hi)))
                angle = rng.randrange(360); opacity = rng.uniform(omin,omax)*min(1,a.wear/60)
                placement = placements.get(cat,'anywhere')
                x,y = rng.choice(interior if placement=='interior' else edge if placement=='edge' and rng.random()<.8 else allowed)
                flip = rng.choice([True,False])
                stamp = tmp/'stamp.miff'
                sc = ['convert',src,'-alpha','set','-background','none','-resize',f'{size}x']
                if flip: sc += ['-flop']
                run(*sc,'-rotate',str(angle),'+repage','-channel','A','-evaluate','multiply',str(opacity),'+channel',stamp)
                sw,sh = dimensions(stamp)
                # Separate stamp files allow one final composition command.
                unique = tmp/f'stamp_{len(layers)}.miff'; stamp.replace(unique)
                cmd += [unique,'-gravity','NorthWest','-geometry',f'{x-sw//2:+d}{y-sh//2:+d}','-compose','Over','-composite','+geometry']
                layers.append(dict(category=cat, file=str(src), width=size, angle=angle, opacity=opacity, x=x,y=y,flip=flip))
            # Composite stamps onto transparent canvas first, mask wear only.
            wear = tmp/'wear.miff'
            cmd[1:2] = ['-size',f'{w}x{h}','xc:none']
            run(*cmd,wear)
            out = a.output/f'tag_{i:03d}.png'
            run('convert',faded,'(',wear,mask,'-gravity','center','-compose','DstIn','-composite',')','-gravity','center','-compose','Over','-composite',base,'-compose','CopyOpacity','-composite',f'PNG32:{out}')
            manifest.append(dict(file=out.name,layers=layers,fade_seed=fade_seed,base_saturation=saturation)); print(f'{out.name}: {len(layers)}/{count} stamps' + (' (category limits reached)' if len(layers)<count else ''),flush=True)
    (a.output/'manifest.json').write_text(json.dumps(dict(seed=a.seed,wear=a.wear,fade=a.fade,fade_scale=a.fade_scale,base_saturation=a.base_saturation,saturation_jitter=a.saturation_jitter,fade_saturation=a.fade_saturation,fade_brightness=a.fade_brightness,base=str(a.base),images=manifest),indent=2))
    preview = a.output.parent/(a.output.name+'-preview.png')
    run('montage',*[a.output/m['file'] for m in manifest],'-thumbnail','600x240','-tile','3x','-geometry','+8+8','-background','#202020',preview)
    print(f'Preview: {preview}')

if __name__ == '__main__': main()

