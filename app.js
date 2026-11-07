// HODOR - Modern Library attendance system
// ضع بيانات مشروع Supabase هنا بعد إنشاء المشروع.
const SUPABASE_URL = "https://qhxzdcazlwpuemdxibmt.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_fPjlAK21Q-icH7d6L3mfqg_aaOhk0aC";
const sbReady = !SUPABASE_URL.includes("YOUR-PROJECT") && !SUPABASE_ANON_KEY.includes("YOUR-SUPABASE");
const db = sbReady && window.supabase?.createClient ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;
let currentUser=null, profile=null, settings=null, attendanceCache=[], employeesCache=[], qrScanner=null, currentQrToken=null;
const $ = id => document.getElementById(id);
const fmtTime = v => v ? new Date(v).toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",hour12:true}) : "—";
const fmtDate = v => new Date(v).toLocaleDateString("ar-EG",{year:"numeric",month:"short",day:"numeric"});
const today = () => new Date().toISOString().slice(0,10);
function toast(msg){const el=$("toast");el.textContent=msg;el.classList.add("show");setTimeout(()=>el.classList.remove("show"),3200)}
function fail(msg){toast(msg)}
function esc(s){return String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))}
function statusLabel(s){return ({present:"حاضر",late:"متأخر",completed:"انصرف",absent:"غائب"})[s]||s||"—"}
function duration(a,b){if(!a||!b)return "—";let n=Math.max(0,(new Date(b)-new Date(a))/3600000);return n.toFixed(2)+" ساعة"}
function localISODate(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`}
function showLogin(){ $("loginView").classList.remove("hidden");$("appView").classList.add("hidden")}
function showApp(){ $("loginView").classList.add("hidden");$("appView").classList.remove("hidden")}
async function login(e){
 e.preventDefault();
 const errBox=$("loginError"), btn=$("loginForm").querySelector('button[type="submit"]');
 errBox.textContent="";
 if(!db){errBox.textContent="تعذر تحميل مكتبة الاتصال أو بيانات Supabase. حدّث الصفحة، ولو استمرت المشكلة ابعتلي صورة.";return}
 btn.disabled=true;btn.textContent="جاري تسجيل الدخول...";
 try{
   const {data,error}=await db.auth.signInWithPassword({email:$("email").value.trim(),password:$("password").value});
   if(error) throw error;
   if(!data.user) throw Error("لم يتم إرجاع بيانات الحساب");
   currentUser=data.user;
   await boot();
 }catch(error){
   errBox.textContent=error.message||"حصل خطأ غير معروف أثناء تسجيل الدخول";
   console.error("HODOR login error:",error);
 }finally{btn.disabled=false;btn.textContent="تسجيل الدخول"}
}
async function boot(){const {data,error}=await db.from("profiles").select("*").eq("id",currentUser.id).single();if(error||!data){fail("الحساب غير مربوط بملف موظف. تواصل مع المدير.");await db.auth.signOut();return}
 profile=data;if(!profile.active){fail("هذا الحساب موقوف. تواصل مع مدير النظام.");await db.auth.signOut();currentUser=null;showLogin();return}showApp();$("userName").textContent=profile.full_name;$("welcomeName").textContent="أهلاً، "+profile.full_name;$("avatar").textContent=profile.full_name?.[0]||"م";$("userRole").textContent=profile.role==="admin"?"مدير النظام":"موظف";
 document.querySelectorAll(".admin-only").forEach(x=>x.classList.toggle("hidden",profile.role!=="admin"));
 $("todayDate").textContent=new Date().toLocaleDateString("ar-EG",{weekday:"long",year:"numeric",month:"long",day:"numeric"});
 await loadSettings();await refreshAll();navigate("overview");subscribeLive()}
function subscribeLive(){db.channel("hodor-live").on("postgres_changes",{event:"*",schema:"public",table:"attendance"},()=>refreshAll()).subscribe()}
async function loadSettings(){const {data}=await db.from("app_settings").select("*").eq("id",1).maybeSingle();settings=data||{latitude:null,longitude:null,radius_m:150,grace_minutes:10};if(settings.latitude!==null){$("latitude").value=settings.latitude;$("longitude").value=settings.longitude}$("radius").value=settings.radius_m||150;$("grace").value=settings.grace_minutes??10}
async function refreshAll(){await loadMyAttendance();if(profile.role==="admin"){await loadEmployees();await loadToday();await loadReports()}}
async function loadMyAttendance(){const {data,error}=await db.from("attendance").select("*").eq("employee_id",currentUser.id).order("work_date",{ascending:false}).limit(45);if(error){fail(error.message);return}attendanceCache=data||[];renderMy();const row=attendanceCache.find(x=>x.work_date===localISODate());$("checkInBtn").disabled=!!row?.check_in;$("checkOutBtn").disabled=!row?.check_in||!!row?.check_out;$("myStatus").textContent=!row?"لم تسجل حضورك اليوم":row.check_out?"تم تسجيل الانصراف": "تم تسجيل الحضور "+fmtTime(row.check_in);$("lateNoteBox").classList.toggle("hidden",!(row?.status==="late"&&row.check_in));$("lateNoteInput").value=row?.late_note||"";$("saveLateNoteBtn").disabled=false;$("saveLateNoteBtn").textContent=row?.late_note?"تحديث الملاحظة":"إرسال الملاحظة"}
async function loadToday(){const {data}=await db.from("attendance").select("*, profiles!attendance_employee_id_fkey(full_name)").eq("work_date",localISODate()).order("check_in");const rows=data||[];$("statPresent").textContent=rows.filter(x=>x.check_in&&!x.check_out).length;$("statLeft").textContent=rows.filter(x=>x.check_out).length;$("statLate").textContent=rows.filter(x=>x.status==="late").length;$("todayRows").innerHTML=rows.map(x=>`<tr><td>${esc(x.profiles?.full_name)}</td><td>${fmtTime(x.check_in)}</td><td>${fmtTime(x.check_out)}</td><td>${duration(x.check_in,x.check_out)}</td><td><span class="status-pill">${statusLabel(x.status)}</span></td><td>${esc(x.late_note||"—")}</td></tr>`).join("")||'<tr><td colspan="6" class="empty">لا توجد سجلات اليوم</td></tr>'}
async function loadEmployees(){const {data}=await db.from("profiles").select("*").order("full_name");employeesCache=data||[];$("statEmployees").textContent=employeesCache.filter(x=>x.active).length;$("employeeRows").innerHTML=employeesCache.map(x=>`<tr><td>${esc(x.full_name)}</td><td>${esc(x.email||"—")}</td><td>${esc(x.shift_start||"09:00")}</td><td>${esc(x.shift_end||"17:00")}</td><td>${x.role==="admin"?"مدير":"موظف"}</td><td><span class="status-pill">${x.active?"نشط":"موقوف"}</span></td><td>${x.id===currentUser.id? "—" : `<button class="btn ${x.active?"secondary":"primary"} employee-toggle" data-id="${esc(x.id)}" data-active="${x.active}" type="button">${x.active?"إيقاف":"إعادة تفعيل"}</button>`}</td></tr>`).join("")}
async function toggleEmployee(id,active){const emp=employeesCache.find(x=>x.id===id);if(!emp)return;if(!confirm(active?`تأكيد إيقاف حساب ${emp.full_name}؟ لن يستطيع تسجيل الدخول، وستظل سجلات حضوره محفوظة.`:`تأكيد إعادة تفعيل حساب ${emp.full_name}؟`))return;const {error}=await db.from("profiles").update({active:!active}).eq("id",id);if(error){fail("تعذر تحديث حالة الموظف: "+error.message);return}toast(active?"تم إيقاف الموظف":"تمت إعادة تفعيل الموظف");await loadEmployees()}
function loadReports(){const from=$("fromDate").value||new Date(Date.now()-30*86400000).toISOString().slice(0,10),to=$("toDate").value||localISODate();const {data}=await db.from("attendance").select("*, profiles!attendance_employee_id_fkey(full_name)").gte("work_date",from).lte("work_date",to).order("work_date",{ascending:false}).limit(1000);const rows=data||[];$("reportRows").innerHTML=rows.map(x=>`<tr><td>${fmtDate(x.work_date)}</td><td>${esc(x.profiles?.full_name)}</td><td>${fmtTime(x.check_in)}</td><td>${fmtTime(x.check_out)}</td><td>${duration(x.check_in,x.check_out)}</td><td>${statusLabel(x.status)}</td><td>${esc(x.late_note||"—")}</td></tr>`).join("")||'<tr><td colspan="7" class="empty">لا توجد نتائج</td></tr>';window.reportCache=rows}
async function saveLateNote(){const note=$("lateNoteInput").value.trim();if(!note){fail("اكتب سبب التأخير أولاً");return}const btn=$("saveLateNoteBtn");btn.disabled=true;const {error}=await db.rpc("save_late_note",{p_note:note});if(error){fail("تعذر حفظ الملاحظة. نفذ كود SQL الخاص بالملاحظات أولاً: "+error.message);btn.disabled=false;return}toast("تم إرسال ملاحظة التأخير للمدير");await loadMyAttendance()}
function renderMy(){$("myRows").innerHTML=attendanceCache.map(x=>`<tr><td>${fmtDate(x.work_date)}</td><td>${fmtTime(x.check_in)}</td><td>${fmtTime(x.check_out)}</td><td>${duration(x.check_in,x.check_out)}</td><td>${statusLabel(x.status)}</td></tr>`).join("")||'<tr><td colspan="5" class="empty">لا توجد سجلات</td></tr>'}
function navigate(page){document.querySelectorAll(".page").forEach(x=>x.classList.add("hidden"));$("page-"+page)?.classList.remove("hidden");document.querySelectorAll(".nav").forEach(x=>x.classList.toggle("active",x.dataset.page===page));const titles={overview:"نظرة عامة",attendance:"الحضور والانصراف",employees:"إدارة الموظفين",reports:"التقارير",settings:"الإعدادات و QR"};$("pageTitle").textContent=titles[page]||"HODOR"}
function getMethod(){return document.querySelector('input[name="method"]:checked').value}
function distance(lat1,lon1,lat2,lon2){const R=6371000,p=Math.PI/180,dLat=(lat2-lat1)*p,dLon=(lon2-lon1)*p,a=Math.sin(dLat/2)**2+Math.cos(lat1*p)*Math.cos(lat2*p)*Math.sin(dLon/2)**2;return 2*R*Math.asin(Math.sqrt(a))}
function getPosition(){return new Promise((resolve,reject)=>{if(!navigator.geolocation)return reject(Error("المتصفح لا يدعم تحديد الموقع"));navigator.geolocation.getCurrentPosition(p=>resolve(p.coords),e=>reject(Error("تعذر تحديد الموقع: "+e.message)),{enableHighAccuracy:true,timeout:15000,maximumAge:0})})}
async function validateLocation(){if(!settings?.latitude||!settings?.longitude)throw Error("المدير لم يحدد موقع المكتبة بعد");const p=await getPosition();const meters=distance(p.latitude,p.longitude,Number(settings.latitude),Number(settings.longitude));if(meters>Number(settings.radius_m||150))throw Error(`أنت خارج نطاق المكتبة (${Math.round(meters)} متر)`);return {lat:p.latitude,lng:p.longitude}}
async function doAttendance(kind){try{let method=getMethod(),loc=null,token=null;if(method==="gps"||method==="qr")loc=await validateLocation();if(method==="qr"){token=currentQrToken;if(!token)throw Error("امسح رمز QR الخاص باليوم أولاً")}
 const {data,error}=await db.rpc(kind==="in"?"record_check_in":"record_check_out",{p_lat:loc?.lat??null,p_lng:loc?.lng??null,p_method:method,p_qr_token:token});if(error)throw error;toast(kind==="in"?"تم تسجيل الحضور بنجاح":"تم تسجيل الانصراف بنجاح");currentQrToken=null;await refreshAll()
 }catch(e){fail(e.message||"حدث خطأ أثناء التسجيل")}}
async function startScan(){if(!window.Html5Qrcode){await loadScannerLib()}if(!window.Html5Qrcode){fail("تعذر تحميل قارئ QR");return}if(qrScanner){await qrScanner.stop().catch(()=>{});qrScanner=null}
 qrScanner=new Html5Qrcode("qrReader");try{await qrScanner.start({facingMode:"environment"},{fps:10,qrbox:{width:220,height:220}},async text=>{try{const parsed=JSON.parse(text);if(!parsed.token)throw Error();currentQrToken=parsed.token;await qrScanner.stop();toast("تم قراءة QR بنجاح. يمكنك تسجيل الحضور أو الانصراف.");}catch{fail("رمز QR غير صالح")}},()=>{})}catch(e){fail("تعذر فتح الكاميرا. استخدم HTTPS واسمح بالكاميرا.")}}
function loadScannerLib(){return new Promise(resolve=>{const s=document.createElement("script");s.src="https://unpkg.com/html5-qrcode";s.onload=resolve;s.onerror=resolve;document.head.appendChild(s)})}
async function generateQR(){try{const {data,error}=await db.from("qr_sessions").insert({created_by:currentUser.id}).select("token,expires_at").single();if(error)throw error;$("adminQr").innerHTML="";new QRCode($("adminQr"),{text:JSON.stringify({token:data.token}),width:180,height:180,colorDark:"#14233a",colorLight:"#ffffff"});$("qrExpiry").textContent="صالح حتى "+new Date(data.expires_at).toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:true});toast("تم إنشاء رمز QR مؤقت")}catch(e){fail(e.message)}}
async function saveSettings(e){e.preventDefault();const payload={id:1,latitude:Number($("latitude").value),longitude:Number($("longitude").value),radius_m:Number($("radius").value),grace_minutes:Number($("grace").value),updated_by:currentUser.id};const {error}=await db.from("app_settings").upsert(payload);if(error)fail(error.message);else{settings=payload;toast("تم حفظ الإعدادات")}}
async function addEmployee(e){e.preventDefault();const email=$("empEmail").value.trim().toLowerCase();const {data:authUsers,error}=await db.from("profiles").select("id").eq("email",email).maybeSingle();if(error||!authUsers){fail("أنشئ حساب الموظف أولاً من Authentication في Supabase بنفس البريد، ثم أعد المحاولة.");return}const {error:upErr}=await db.from("profiles").update({full_name:$("empName").value,shift_start:$("empStart").value,shift_end:$("empEnd").value}).eq("id",authUsers.id);if(upErr)fail(upErr.message);else{toast("تم تحديث بيانات الموظف");$("employeeForm").reset();await loadEmployees()}}
function exportCSV(){const rows=window.reportCache||[];const header=["التاريخ","الموظف","الحضور","الانصراف","الحالة"];const lines=[header,...rows.map(x=>[x.work_date,x.profiles?.full_name||"",x.check_in||"",x.check_out||"",statusLabel(x.status)])];const csv="\uFEFF"+lines.map(r=>r.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(",")).join("\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));a.download="HODOR-attendance.csv";a.click();URL.revokeObjectURL(a.href)}
const HODOR_THEMES=["blue","emerald","purple","midnight","rose","orange","teal","red","cyan","indigo","gold","graphite","mint","coral","ocean","lavender","forest","ruby","sand","neon"];
function applyTheme(name){const safe=HODOR_THEMES.includes(name)?name:"blue";document.body.dataset.theme=safe;const picker=$("themeSelect");if(picker)picker.value=safe;try{localStorage.setItem("hodor-theme",safe)}catch(e){}}
const savedTheme=(()=>{try{return localStorage.getItem("hodor-theme")||"blue"}catch(e){return "blue"}})();
applyTheme(savedTheme);
$("themeSelect")?.addEventListener("change",e=>applyTheme(e.target.value));
function clock(){const d=new Date();$("liveClock").textContent=d.toLocaleTimeString("ar-EG",{hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:true});$("liveDate").textContent=d.toLocaleDateString("ar-EG",{weekday:"long",year:"numeric",month:"long",day:"numeric"})}
const loginForm=$("loginForm"); if(loginForm){loginForm.addEventListener("submit",login);const loginButton=loginForm.querySelector('button[type="submit"]');loginButton?.addEventListener("click",e=>{e.preventDefault();if(loginForm.reportValidity())loginForm.requestSubmit()});} $("logoutBtn")?.addEventListener("click",async()=>{if(db)await db.auth.signOut();location.reload()});
document.querySelectorAll(".nav").forEach(b=>b.addEventListener("click",()=>navigate(b.dataset.page)));document.querySelectorAll("[data-goto]").forEach(b=>b.addEventListener("click",()=>navigate(b.dataset.goto)));
$("checkInBtn").addEventListener("click",()=>doAttendance("in"));$("checkOutBtn").addEventListener("click",()=>doAttendance("out"));$("saveLateNoteBtn").addEventListener("click",saveLateNote);
document.querySelectorAll('input[name="method"]').forEach(r=>r.addEventListener("change",()=>{$("qrArea").classList.toggle("hidden",getMethod()!=="qr")}));
$("scanBtn").addEventListener("click",startScan);$("generateQr").addEventListener("click",generateQR);$("settingsForm").addEventListener("submit",saveSettings);$("employeeForm").addEventListener("submit",addEmployee);$("employeeRows").addEventListener("click",e=>{const b=e.target.closest(".employee-toggle");if(b)toggleEmployee(b.dataset.id,b.dataset.active==="true")});$("filterBtn").addEventListener("click",loadReports);$("exportBtn").addEventListener("click",exportCSV);
setInterval(clock,1000);clock();
if(db){
 db.auth.getSession().then(({data,error})=>{
   if(error){$("loginError").textContent="تعذر الاتصال بخدمة تسجيل الدخول: "+error.message;return}
   if(data.session){currentUser=data.session.user;boot().catch(e=>{$("loginError").textContent=e.message||"تعذر تحميل حسابك";console.error(e)})}
 }).catch(e=>{$("loginError").textContent="تعذر الاتصال: "+(e.message||e);console.error(e)});
}else{$("loginError").textContent="مكتبة Supabase لم تُحمّل. تأكد من اتصال الإنترنت ثم حدّث الصفحة."}