def num(n,h):return ''.join(f'<img class="d" style="height:{h}px" src="icons/n{c}.webp" alt="">' for c in str(n))
URL='yoursite.com/poll'
def foot(dark=False):return f'<div class="ft"><span>The Feral Collective</span><span>{URL}</span></div>'
def shell(kind,size,inner,art,theme):
    H=1920 if size=='story' else 1350
    return f'<div class="card {theme} {size}" data-name="{kind}-{size}" style="height:{H}px">{art}<div class="in">{inner}</div></div>'
def A(size,theme):
    H=size=='story'
    art='<img class="art a1" src="art/red.webp" alt="">'
    inner=f'''<div class="eye"><i></i>Halloween Horror Movie Poll</div>
<div class="sp"></div>
<div class="cat">Takes charge in a panic</div>
<div class="nm" style="font-size:{300 if H else 250}px">Heather</div>
<img class="ul" src="icons/underline.webp" alt="">
<div class="vt">{num(13,280 if H else 210)}<span>votes</span></div>
<p class="j nar">Thirteen of you saw the chaos and said “her.” Brave.</p>
<div class="sp"></div>{foot()}'''
    return shell('winner',size,inner,art,theme)
def B(size,theme):
    H=size=='story'
    wins=['Silent, then the right tool','“Bad feeling” but opens the door','Runs fast in heels or one sock','“I’ll be fine, go without me”']
    li=''.join(f'<li><b>{i+1}</b>{w}</li>' for i,w in enumerate(wins))
    art='<img class="art a1" src="art/drip.webp" alt="">'
    inner=f'''<div class="eye"><i></i>My horror movie results</div>
<div class="sp"></div>
<div class="cat">In the movie, I am</div>
<div class="nm" style="font-size:{230 if H else 190}px">Andrada</div>
<div class="vt">{num(4,280 if H else 200)}<span>golds</span></div>
<ul class="lst">{li}</ul>
<p class="j">Opens the door anyway.</p>
<div class="sp"></div>{foot()}'''
    return shell('personal',size,inner,art,theme)
def C(size,theme):
    H=size=='story'
    art='<img class="art a1" src="art/loop.webp" alt="">'
    inner=f'''<div class="eye"><i></i>Most golds won</div>
<div class="sp"></div>
<div class="nm" style="font-size:{300 if H else 250}px">Ed D.<br>Mame</div>
<div class="vt">{num(6,300 if H else 220)}<span>golds</span></div>
<p class="j">Names the zombies, jokes at the worst moment, volunteers first, and walks into the abandoned building. We will miss you, Ed.</p>
<div class="sp"></div>{foot()}'''
    return shell('golds',size,inner,art,theme)
cards=[('Category winner','paper',A),('Personal results','paper',B),('Most golds','ink',C)]
css=open('cards.css').read()
def page(full):
    body=''
    for lab,th,f in cards:
        body+=f'<section class="grp"><h2>{lab}</h2><div class="row">'
        for sz in('story','square'):
            body+=f'<figure class="fig {sz}"><div class="pv">{f(sz,th)}</div><figcaption>{"Story 1080×1920" if sz=="story" else "Feed 1080×1350"}</figcaption></figure>'
        body+='</div></section>'
    if full: body='<div id="full">'+''.join(f(sz,th) for _,th,f in cards for sz in('story','square'))+'</div>'
    head='<h1>Share cards</h1><p class="lead">Pick the look. Safe zones are marked on the Story cards. Real cards would be made for every winner and person.</p>' if not full else ''
    return f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Share Cards</title><style>{css}</style></head><body class="{"fullpage" if full else ""}">{head}{body}</body></html>'
open('index.html','w').write(page(False));open('full.html','w').write(page(True))
