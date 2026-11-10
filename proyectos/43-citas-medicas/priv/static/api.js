/* MediCitas - cliente de la API de citas (Erlang/cowboy).
 * Compartido por agendar.html y panel.html. */

// Servido por cowboy: mismo origen. Si se abre el archivo suelto, apunta a localhost.
const API = location.protocol === 'file:' ? 'http://localhost:8080' : '';

const MEDICOS = {
  1:  { nombre: 'Dr. Alejandro Morales', esp: 'Cardiología',          box: 102 },
  2:  { nombre: 'Dra. Elena Vega',       esp: 'Pediatría',            box: 204 },
  3:  { nombre: 'Dr. Carlos Mendoza',    esp: 'Medicina General',     box: 105 },
  4:  { nombre: 'Dra. Sofía Ramírez',    esp: 'Dermatología',         box: 301 },
  5:  { nombre: 'Dr. Roberto Gómez',     esp: 'Traumatología',        box: 110 },
  6:  { nombre: 'Dra. Mariana Castro',   esp: 'Ginecología',          box: 208 },
  7:  { nombre: 'Dr. Javier Ortiz',      esp: 'Neurología',           box: 402 },
  8:  { nombre: 'Dra. Lucía Navarro',    esp: 'Oftalmología',         box: 315 },
  9:  { nombre: 'Dr. Fernando Silva',    esp: 'Otorrinolaringología', box: 112 },
  10: { nombre: 'Dra. Patricia Ramos',   esp: 'Endocrinología',       box: 219 }
};

const ERRORES = {
  horario_ocupado:   'El médico ya tiene una cita que se traslapa con ese horario.',
  intervalo_invalido:'El intervalo de horas no es válido (la hora de fin debe ser mayor que la de inicio).',
  fecha_invalida:    'La fecha no es válida.',
  medico_no_existe:  'El médico seleccionado no existe.',
  cita_duplicada:    'Ya existe una cita con ese identificador.',
  no_existe:         'La cita no existe.'
};

function textoError(data, crudo) {
  let e = data;
  if (e && typeof e === 'object') e = e.error || e.razon || e.reason || e.message || JSON.stringify(e);
  if (!e) e = crudo || 'Error desconocido';
  e = String(e);
  if (ERRORES[e]) return ERRORES[e];
  // transiciones invalidas del estado de la cita, p. ej. {transicion_invalida, atendida, cancelar}
  return e.replace(/_/g, ' ');
}

/* Devuelve siempre { ok, status, data, error } y nunca lanza. */
async function api(metodo, ruta, cuerpo) {
  let res;
  try {
    res = await fetch(API + ruta, {
      method: metodo,
      headers: cuerpo ? { 'Content-Type': 'application/json' } : {},
      body: cuerpo ? JSON.stringify(cuerpo) : undefined
    });
  } catch (e) {
    return { ok: false, status: 0, error: 'No hay conexión con el servidor. ¿Está corriendo la aplicación?' };
  }
  const crudo = await res.text();
  let data = null;
  try { data = crudo ? JSON.parse(crudo) : null; } catch (e) { /* no era JSON */ }
  if (!res.ok) return { ok: false, status: res.status, data, error: textoError(data, crudo) };
  return { ok: true, status: res.status, data };
}

/* ---------- helpers de fecha y hora ---------- */
const pad = n => String(n).padStart(2, '0');
const aMin = hhmm => { const [h, m] = String(hhmm).split(':'); return (+h) * 60 + (+m); };
const aHHMM = min => pad(Math.floor(min / 60)) + ':' + pad(min % 60);

function hoyISO(delta = 0) {
  const d = new Date();
  d.setDate(d.getDate() + delta);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}
const MESES = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
function fechaBonita(iso) {
  const [y, m, d] = String(iso).split('-');
  return `${+d} ${MESES[+m - 1] || '?'} ${y}`;
}

/* ---------- normalizadores (toleran variantes de formato del JSON) ---------- */
function normHora(v) {
  if (typeof v === 'number') return aHHMM(v);
  return String(v).slice(0, 5);
}
function normFecha(v) {
  if (Array.isArray(v)) return `${v[0]}-${pad(v[1])}-${pad(v[2])}`;
  return String(v).slice(0, 10);
}
function normEstado(s) {
  s = String(s || '').toLowerCase().replace(/[-\s]/g, '_');
  if (s.startsWith('confirm')) return 'confirmada';
  if (s.startsWith('atend'))   return 'atendida';
  if (s.startsWith('cancel'))  return 'cancelada';
  if (s.startsWith('no_show') || s === 'noshow') return 'no_show';
  return 'agendada';
}
function normCita(c) {
  return {
    id: c.id,
    paciente: String(c.paciente ?? ''),
    medico: Number(c.medico),
    fecha: normFecha(c.fecha),
    inicio: normHora(c.inicio),
    fin: normHora(c.fin),
    estado: normEstado(c.estado)
  };
}
function normLista(data) {
  const arr = Array.isArray(data) ? data : (data && (data.citas || data.items)) || [];
  return arr.map(normCita);
}
/* Agenda de un dia -> [{ini, fin, id}] en minutos, ordenada. */
function normAgenda(data) {
  const arr = Array.isArray(data) ? data : (data && (data.agenda || data.citas)) || [];
  return arr.map(x => {
    if (Array.isArray(x)) return { ini: aMin(normHora(x[0])), fin: aMin(normHora(x[1])), id: x[2] };
    return { ini: aMin(normHora(x.inicio)), fin: aMin(normHora(x.fin)), id: x.id ?? x.cita_id ?? x.cita };
  }).sort((a, b) => a.ini - b.ini);
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
