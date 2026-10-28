(function(){
  function stopVeil(canvas){
    if(!canvas)return;
    if(canvas.__veilRaf){
      cancelAnimationFrame(canvas.__veilRaf);
      canvas.__veilRaf=0;
    }
    canvas.__veilRunning=false;
    canvas.__veilGl=null;
  }

  function initDarkVeil(force){
    var canvas=document.getElementById('darkveilCanvas');
    if(!canvas)return;
    var glPrev=canvas.__veilGl;
    var alive=!!(canvas.__veilRunning && glPrev && !glPrev.isContextLost());
    if(!force && alive)return;
    stopVeil(canvas);

    var gl=canvas.getContext('webgl',{alpha:false,antialias:false,preserveDrawingBuffer:true});
    if(!gl || gl.isContextLost())return;
    canvas.__veilGl=gl;
    canvas.__veilRunning=true;

    if(!canvas.__veilCtxBound){
      canvas.__veilCtxBound=true;
      canvas.addEventListener('webglcontextlost',function(e){
        e.preventDefault();
        stopVeil(canvas);
      },false);
      canvas.addEventListener('webglcontextrestored',function(){
        initDarkVeil(true);
      },false);
    }

    var vertex=[
      'attribute vec2 position;',
      'void main(){',
      '  gl_Position = vec4(position, 0.0, 1.0);',
      '}'
    ].join('\n');

    var fragment=[
      'precision highp float;',
      'uniform vec2 uResolution;',
      'uniform float uTime;',
      'uniform vec3 uAccent;',
      'uniform float uNoise;',
      'uniform float uScan;',
      'uniform float uScanFreq;',
      'uniform float uWarp;',
      'float rand(vec2 p){',
      '  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);',
      '}',
      'float noise(vec2 p){',
      '  vec2 i = floor(p);',
      '  vec2 f = fract(p);',
      '  vec2 u = f * f * (3.0 - 2.0 * f);',
      '  return mix(mix(rand(i), rand(i + vec2(1.0, 0.0)), u.x), mix(rand(i + vec2(0.0, 1.0)), rand(i + vec2(1.0, 1.0)), u.x), u.y);',
      '}',
      'float fbm(vec2 p){',
      '  float v = 0.0;',
      '  float a = 0.5;',
      '  mat2 r = mat2(0.8, -0.6, 0.6, 0.8);',
      '  for(int i = 0; i < 5; i++){',
      '    v += a * noise(p);',
      '    p = r * p * 2.02 + 11.7;',
      '    a *= 0.5;',
      '  }',
      '  return v;',
      '}',
      'void main(){',
      '  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / min(uResolution.x, uResolution.y);',
      '  float t = uTime * 0.46;',
      '  vec2 p = uv;',
      '  p.x += sin(p.y * 3.2 + t * 1.5) * 0.12 * uWarp;',
      '  p.y += cos(p.x * 4.1 - t * 1.15) * 0.16 * uWarp;',
      '  float cloth = 0.0;',
      '  for(int i = 0; i < 5; i++){',
      '    float fi = float(i);',
      '    vec2 q = p;',
      '    q.x += sin(q.y * (2.0 + fi * 0.45) + t * (1.1 + fi * 0.13)) * (0.18 + fi * 0.012);',
      '    q.y += cos(q.x * (1.7 + fi * 0.38) - t * (0.8 + fi * 0.11)) * 0.11;',
      '    float n = fbm(q * (1.6 + fi * 0.32) + vec2(t * 0.28, -t * 0.2));',
      '    float ribbon = sin((q.x * 1.32 + q.y * (0.78 + fi * 0.11) + n * 1.9 + t * (0.42 + fi * 0.08)) * 4.6);',
      '    cloth += smoothstep(0.42, 1.0, ribbon) * (0.18 + fi * 0.045);',
      '  }',
      '  float bloom = smoothstep(0.05, 1.28, cloth);',
      '  float core = smoothstep(0.82, 1.8, cloth);',
      '  float centerFade = smoothstep(1.25, 0.05, length(uv * vec2(0.74, 1.02)));',
      '  float scanline = sin(gl_FragCoord.y * uScanFreq) * 0.5 + 0.5;',
      '  vec3 base = vec3(0.006, 0.008, 0.03);',
      '  vec3 color = base;',
      '  color += uAccent * bloom * (0.24 + centerFade * 0.7);',
      '  color += vec3(0.92, 0.96, 1.0) * core * 0.58;',
      '  color += vec3(0.12, 0.2, 0.78) * fbm(uv * 2.2 + t) * 0.18;',
      '  color *= 1.0 - scanline * scanline * uScan;',
      '  color += (rand(gl_FragCoord.xy + uTime) - 0.5) * uNoise;',
      '  float vignette = smoothstep(1.45, 0.18, length(uv));',
      '  color *= 0.58 + vignette * 0.8;',
      '  gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);',
      '}'
    ].join('\n');

    function compile(type,source){
      var shader=gl.createShader(type);
      gl.shaderSource(shader,source);
      gl.compileShader(shader);
      if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){
        console.error(gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
      }
      return shader;
    }

    var vertexShader=compile(gl.VERTEX_SHADER,vertex);
    var fragmentShader=compile(gl.FRAGMENT_SHADER,fragment);
    if(!vertexShader||!fragmentShader){
      stopVeil(canvas);
      return;
    }

    var program=gl.createProgram();
    gl.attachShader(program,vertexShader);
    gl.attachShader(program,fragmentShader);
    gl.linkProgram(program);
    if(!gl.getProgramParameter(program,gl.LINK_STATUS)){
      console.error(gl.getProgramInfoLog(program));
      stopVeil(canvas);
      return;
    }

    var buffer=gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);

    var position=gl.getAttribLocation(program,'position');
    var uResolution=gl.getUniformLocation(program,'uResolution');
    var uTime=gl.getUniformLocation(program,'uTime');
    var uAccent=gl.getUniformLocation(program,'uAccent');
    var uNoise=gl.getUniformLocation(program,'uNoise');
    var uScan=gl.getUniformLocation(program,'uScan');
    var uScanFreq=gl.getUniformLocation(program,'uScanFreq');
    var uWarp=gl.getUniformLocation(program,'uWarp');
    var start=window.__mineradioVeilStart||performance.now();
    window.__mineradioVeilStart=start;

    function resize(){
      if(gl.isContextLost())return;
      var dpr=Math.min(window.devicePixelRatio||1,1.75);
      var width=Math.max(1,Math.floor(canvas.clientWidth*dpr));
      var height=Math.max(1,Math.floor(canvas.clientHeight*dpr));
      if(canvas.width!==width||canvas.height!==height){
        canvas.width=width;
        canvas.height=height;
        gl.viewport(0,0,width,height);
      }
    }

    function draw(){
      if(gl.isContextLost()){
        stopVeil(canvas);
        return;
      }
      resize();
      gl.useProgram(program);
      gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
      gl.enableVertexAttribArray(position);
      gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
      gl.uniform2f(uResolution,canvas.width,canvas.height);
      gl.uniform1f(uTime,(performance.now()-start)/1000);
      gl.uniform3f(uAccent,48/255,77/255,247/255);
      gl.uniform1f(uNoise,0.035);
      gl.uniform1f(uScan,0.035);
      gl.uniform1f(uScanFreq,1.7);
      gl.uniform1f(uWarp,1.0);
      gl.drawArrays(gl.TRIANGLES,0,3);
      gl.flush();
      canvas.__veilRaf=requestAnimationFrame(draw);
    }

    if(!canvas.__veilResizeBound){
      canvas.__veilResizeBound=true;
      window.addEventListener('resize',function(){
        if(canvas.__veilRunning)resize();
      });
    }
    draw();
  }

  window.__mrDarkVeil = initDarkVeil;

  /* Wait for DC runtime to replace <x-dc> with #dc-root before binding WebGL.
     Early init on the throwaway template canvas loses context and blocks restart. */
  function bootWhenReady(){
    var tries=0;
    function tick(){
      tries++;
      var canvas=document.getElementById('darkveilCanvas');
      var ready=!!(canvas && (document.getElementById('dc-root') || tries>60));
      if(ready){
        initDarkVeil(true);
        return;
      }
      setTimeout(tick,50);
    }
    tick();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bootWhenReady);
  else bootWhenReady();
})();
