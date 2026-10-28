import sys
def check(path):
    s=open(path,encoding='utf-8').read()
    i=0;n=len(s);stack=[];line=1
    pairs={')':'(',']':'[','}':'{'}
    # string handling with interpolation
    def skip_string(i,line):
        raw=False
        if s[i]=='r': raw=True;i+=1
        q=s[i]
        triple=s[i:i+3]==q*3
        i+= 3 if triple else 1
        while i<n:
            c=s[i]
            if c=='\n': line+=1
            if not raw and c=='\\': i+=2;continue
            if triple and s[i:i+3]==q*3: return i+3,line
            if not triple and c==q: return i+1,line
            if not raw and c=='$' and i+1<n and s[i+1]=='{':
                i,line=skip_code(i+2,line,'}')
                continue
            i+=1
        raise Exception('unterminated string at line %d'%line)
    def skip_code(i,line,end):
        depth=0
        while i<n:
            c=s[i]
            if c=='\n': line+=1
            if s[i:i+2]=='//':
                while i<n and s[i]!='\n': i+=1
                continue
            if s[i:i+2]=='/*':
                j=s.index('*/',i); line+=s[i:j].count('\n'); i=j+2; continue
            if c in '\'"' or (c=='r' and i+1<n and s[i+1] in '\'"' and not (s[i-1].isalnum() or s[i-1]=='_')):
                i,line=skip_string(i,line); continue
            if c=='{': depth+=1
            elif c=='}':
                if depth==0 and end=='}': return i+1,line
                depth-=1
            i+=1
        return i,line
    while i<n:
        c=s[i]
        if c=='\n': line+=1
        if s[i:i+2]=='//':
            while i<n and s[i]!='\n': i+=1
            continue
        if s[i:i+2]=='/*':
            j=s.index('*/',i); line+=s[i:j].count('\n'); i=j+2; continue
        if c in '\'"' or (c=='r' and i+1<n and s[i+1] in '\'"' and not (s[i-1].isalnum() or s[i-1]=='_')):
            i,line=skip_string(i,line); continue
        if c in '([{': stack.append((c,line))
        elif c in ')]}':
            if not stack or stack[-1][0]!=pairs[c]:
                return 'MISMATCH %s at line %d (open %s)'%(c,line,stack[-1] if stack else None)
            stack.pop()
        i+=1
    if stack: return 'UNCLOSED %s'%(stack[-5:],)
    return None
bad=0
for p in sys.argv[1:]:
    try:
        r=check(p)
    except Exception as e:
        r=str(e)
    if r: bad+=1; print(p,r)
print('checked',len(sys.argv)-1,'bad',bad)
