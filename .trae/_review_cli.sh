#!/bin/bash
# 使用 agent-browser CLI 顺序复审 TR-1.1/1.2/3.1/4.1/4.2/5.1 rubric
set -u
BASE="http://127.0.0.1:8765/index.html"
OUT="/tmp/review_runs"
mkdir -p "$OUT"
export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix review)"
echo "session=$AGENT_BROWSER_SESSION"
LOG="$OUT/cli_review.log"
: > "$LOG"
log() { echo "$*" | tee -a "$LOG" ; }

agent-browser open "$BASE" >> "$LOG" 2>&1
agent-browser wait --load networkidle >> "$LOG" 2>&1
sleep 2

# ====================== TR-1.2: changelog button has type=button
log "=== TR-1.2 === type=button 断言"
agent-browser eval --js '(() => { const b = document.querySelector("button[data-i18n=\"foot_clog\"]"); return JSON.stringify({ok:!!b,type:b?.getAttribute?.("type"),text:b?.innerText?.slice(0,40)}); })()' > $OUT/tr12.json 2>>$LOG || true
cat $OUT/tr12.json | tee -a "$LOG"
log ""

# ====================== TR-5.1: {{ x }} never resolved 次数
log "=== TR-5.1 === 控制台警告检索"
agent-browser eval --js '(()=>{ const q = JSON.stringify(window.__dc_runtime_warnings__ || {count:0}); return q; })()' > $OUT/tr51_pre.json 2>>$LOG
cat $OUT/tr51_pre.json | tee -a "$LOG"
# 更稳：hook console.warn 并滚动触发挂载，扫描
agent-browser eval --js '(()=>{ window.__tr51 = []; const w=console.warn.bind(console); const e=console.error.bind(console); console.warn=(...a)=>{window.__tr51.push("W"+a.join(" ")); w(...a);}; console.error=(...a)=>{window.__tr51.push("E"+a.join(" ")); e(...a);}; window.scrollTo(0,document.body.scrollHeight); return "hooked"; })()' >>$LOG 2>&1
sleep 3
agent-browser eval --js '(()=>{ const s = (window.__tr51||[]).join("\n"); const n = ((s||"").match(/\{\{ x \}\} never resolved/g)||[]).length; return JSON.stringify({hit:n,tail:(s||"").split("\n").slice(-20).join(" \\n ")}); })()' > $OUT/tr51.json 2>>$LOG
cat $OUT/tr51.json | tee -a "$LOG"
log ""

# ====================== TR-1.1: click changelog -> modal 含 releases <a>
log "=== TR-1.1 === 点击更新日志 Modal 含 GitHub Releases 链接"
# 先用 find/role 点按钮
agent-browser click 'button[data-i18n="foot_clog"]' >>$LOG 2>&1
sleep 2
agent-browser snapshot -i -u > $OUT/tr11_snap.txt 2>>$LOG || true
head -80 $OUT/tr11_snap.txt | tee -a "$LOG"
agent-browser eval --js '(()=>{ const mask = Array.from(document.querySelectorAll("*")).find(n=>n.getAttribute && n.getAttribute("data-clog-mask")!==null); const vis = !!mask && mask.getBoundingClientRect().width>0; const a = mask ? mask.querySelector("a[href=\"https://github.com/XxHuberrr/Mineradio/releases\"]") : null; return JSON.stringify({maskFound:!!mask, maskVisible:vis, aFound:!!a, targetBlank:a?.target==="_blank", relNoReferrer:(a?.rel||"").includes("noreferrer"), text:a?.innerText?.trim()?.slice(0,60)}); })()' > $OUT/tr11.json 2>>$LOG
cat $OUT/tr11.json | tee -a "$LOG"
agent-browser screenshot "$OUT/tr1-clog.png" 2>>$LOG
# 关闭 Modal，按 Esc
agent-browser press Escape >>$LOG 2>&1
log ""

# ====================== TR-3.1: EN 模式下评价区无中文字符
log "=== TR-3.1 === EN 模式下评价区无中文"
agent-browser open "$BASE" >> "$LOG" 2>&1
agent-browser wait --load networkidle >> $LOG 2>&1
sleep 2
agent-browser eval --js '(()=>{ try { const T = window.I18N || (window.__COMPONENT_I18N__); const L = "en"; if (!T) return "no-I18N"; document.documentElement.setAttribute("lang","en"); document.documentElement.setAttribute("data-locale","en"); localStorage.setItem("i18n","en"); const root = document.getElementById("root"); if (root) { root.querySelectorAll("[data-i18n]").forEach(el=>{const k=el.getAttribute("data-i18n"); if (T[k]){ const v = typeof T[k][L]==="string"?T[k][L]:T[k]["zh"]; el.textContent=v; if(/INPUT|TEXTAREA/.test(el.tagName)) el.value=v;}}); root.querySelectorAll("[data-i18n-html]").forEach(el=>{const k=el.getAttribute("data-i18n-html"); if (T[k]) el.innerHTML=typeof T[k][L]==="string"?T[k][L]:T[k]["zh"];}); ["title","alt","aria-label","placeholder"].forEach(a=>{root.querySelectorAll(`[data-i18n-${a}]`).forEach(el=>{const k=el.getAttribute("data-i18n-"+a); if (T[k]) el.setAttribute(a,typeof T[k][L]==="string"?T[k][L]:T[k]["zh"]);});});} return "applied";} catch(e){return "err:"+String(e);} })()' > $OUT/tr31_apply.json 2>>$LOG
cat $OUT/tr31_apply.json | tee -a "$LOG"
sleep 1
agent-browser eval --js '(()=>{ const s=document.getElementById("praise"); if (!s) return JSON.stringify({ok:false,reason:"no #praise"}); const w=document.createTreeWalker(s,NodeFilter.SHOW_TEXT,null); let t=""; while(true){const n=w.nextNode(); if (!n) break; const v=(n.nodeValue||"").trim(); if (v) t += v + "\n";} const m=(t.match(/[\u4e00-\u9fff]/g)||[]); return JSON.stringify({ok:m.length===0,count:m.length,sample:m.slice(0,30).join(""),preview:t.slice(0,400)}); })()' > $OUT/tr31.json 2>>$LOG
cat $OUT/tr31.json | tee -a "$LOG"
agent-browser screenshot "$OUT/tr3-praise-en.png" 2>>$LOG
log ""

# ====================== TR-4.1 / TR-4.2: hash -> anchor 映射 4 组
log "=== TR-4.x === 4 组 hash 映射"
for PAIR in "功能:features" "下载:download" "评价:praise" "资助我们:support"; do
  KEY=${PAIR%:*}
  EXPECT=${PAIR#*:}
  agent-browser open "${BASE}#$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$KEY")" >> $LOG 2>&1
  agent-browser wait --load networkidle >> $LOG 2>&1
  sleep 2
  agent-browser get url > $OUT/tr4_url_${EXPECT}.txt 2>>$LOG
  agent-browser eval --js '(()=>{ const exp = "'$EXPECT'"; const h = window.location.hash.replace(/^#/,""); const el = document.getElementById(exp); const r = el?el.getBoundingClientRect():null; return JSON.stringify({hash:h, foundHref:decodeURIComponent(h), expect:exp, elFound:!!el, top:r?r.top:null}); })()' > $OUT/tr4_${EXPECT}.json 2>>$LOG
  log "Sample KEY=$KEY EXPECT=$EXPECT"
  cat $OUT/tr4_${EXPECT}.json | tee -a "$LOG"
done

agent-browser close --all >> $LOG 2>&1
log ""
log "=== DONE. logs at $OUT/ ==="
ls -la "$OUT"
