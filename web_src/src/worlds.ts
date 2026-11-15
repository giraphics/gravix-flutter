/**
 * `window.GravixWorlds`: gravix-quasar's three worlds (plus a fourth, "traffic",
 * that shows a gravix-sim-backend run) behind one small API that
 * Flutter calls the same way on every platform.
 *
 *   mount(kind, host, launchJson)  -> Promise<string>   backend name once running
 *   state(kind)                    -> string             JSON snapshot for the UI
 *   invoke(kind, action, argsJson)                       one control change
 *   dispose(kind)
 *   launchFromUrl()                -> string             ?backend / ?failDevice / ?points
 *
 * On the web all three worlds live in one page (one HtmlElementView each). On
 * Windows and Android each world is its own WebView page (assets/www/world.html)
 * holding one of them. Either way Dart only ever sees these five functions.
 *
 * The world set-up is gravix-quasar's TerrainPanel / PointCloudPanel /
 * HierarchyPanel logic with the Vue removed; lib/ is copied from it unchanged.
 */
import {
  BackendPreference,
  GravixEngine,
  PointCloudSimulationSystem,
  addPointCloud,
  type GravixEngineOptions,
  type PointCloudRecord,
} from '@giraphics/gravix-engine';
import { BabylonBackend } from '@giraphics/gravix-engine/babylon';

import { MARKER_TOPOLOGY, TERRAIN_TOPOLOGY, buildMarker, buildTerrain } from './lib/geometry.js';
import { LorenzAttractorSystem } from './lib/lorenz-attractor.js';
import { spawnDynamicMesh } from './lib/mesh.js';
import { ParentOrbitSystem } from './lib/orbit.js';
import { createTraffic } from './traffic.js';

type WorldKind = 'terrain' | 'cloud' | 'hierarchy' | 'traffic';

interface Launch {
  backend: 'auto' | 'webgl';
  failDevice: boolean;
  points: number;
  /** Base WebSocket address of a gravix-sim-backend; empty means not set. */
  sim: string;
}

/** What every world shares: an engine on a canvas that tracks its host's size. */
interface Running {
  engine: GravixEngine;
  backend: BabylonBackend;
}

interface World {
  /** World-specific fields for state(). */
  snapshot(): Record<string, unknown>;
  invoke(action: string, args: unknown[]): void;
  /** Release anything the world holds outside the engine (sockets, timers). */
  dispose?(): void;
}

interface Mounted {
  kind: WorldKind;
  running: Running | null;
  world: World | null;
  error: string | null;
  cancelled: boolean;
  teardown: () => void;
}

const DEFAULT_POINTS = 300_000;
const mounted = new Map<WorldKind, Mounted>();

// ---------------------------------------------------------------------------
// Launch options: the same query flags gravix-quasar reads.

function queryParams(): URLSearchParams {
  const params = new URLSearchParams(window.location.search);
  const hashQuery = window.location.hash.indexOf('?');
  if (hashQuery >= 0) {
    for (const [key, value] of new URLSearchParams(window.location.hash.slice(hashQuery))) {
      if (!params.has(key)) params.set(key, value);
    }
  }
  return params;
}

function launchFromUrl(): string {
  const params = queryParams();
  const points = Number(params.get('points') ?? DEFAULT_POINTS);
  const launch: Launch = {
    backend: params.get('backend') === 'webgl' ? 'webgl' : 'auto',
    failDevice: params.get('failDevice') === '1',
    points: Number.isFinite(points) && points > 0 ? Math.floor(points) : DEFAULT_POINTS,
    sim: params.get('sim') ?? '',
  };
  return JSON.stringify(launch);
}

function parseLaunch(json: string | undefined): Launch {
  const fallback = JSON.parse(launchFromUrl()) as Launch;
  if (!json) return fallback;
  const given = JSON.parse(json) as Partial<Launch>;
  const points = Number(given.points ?? fallback.points);
  return {
    backend: given.backend === 'webgl' ? 'webgl' : 'auto',
    failDevice: given.failDevice === true,
    points: Number.isFinite(points) && points > 0 ? Math.floor(points) : DEFAULT_POINTS,
    sim: typeof given.sim === 'string' ? given.sim : fallback.sim,
  };
}

// ---------------------------------------------------------------------------
// The worlds. Each `create*` configures a fresh engine, like the
// `configure` callback each Vue panel passed to useGravixEngine.

function createTerrain(engine: GravixEngine): World {
  engine.createCamera({
    name: 'terrain-camera',
    fov: Math.PI / 4,
    nearPlane: 0.5,
    farPlane: 5000,
    position: [120, 72, 120],
    target: [0, 0, 0],
  });
  const geometry = buildTerrain(48, 60);
  const { entity, mesh } = spawnDynamicMesh(engine, 'terrain-layer', geometry, TERRAIN_TOPOLOGY);
  const indexCount = geometry.indexCount;
  mesh.setDrawCount(indexCount);
  let visible = true;
  let percent = 100;

  return {
    snapshot: () => ({
      visible,
      percent,
      indexCount,
      drawn: Math.round(indexCount * (percent / 100)),
      verts: indexCount,
    }),
    invoke(action, args) {
      if (action === 'setVisible') {
        visible = args[0] === true;
        engine.world.components.Renderable.visible[entity.eid] = visible ? 1 : 0;
      } else if (action === 'setPercent') {
        percent = clamp(Number(args[0]), 0, 100);
        mesh.setDrawCount(Math.round(indexCount * (percent / 100)));
      }
    },
  };
}

function createCloud(engine: GravixEngine, launch: Launch, bounce: PointCloudSimulationSystem, lorenz: LorenzAttractorSystem): World {
  engine.createCamera({
    name: 'cloud-camera',
    fov: Math.PI / 4,
    nearPlane: 0.1,
    farPlane: 500,
    position: [14, 8, 18],
    target: [0, 0, 0],
  });
  const entity = engine.world.entities.create('cloud');
  const record: PointCloudRecord = addPointCloud(engine.world, entity, {
    capacity: launch.points,
    pointSize: 2,
  });
  lorenz.prime(entity.eid, record);

  let visible = true;
  let animate = true;
  let demo: 'lorenz' | 'bounce' = 'lorenz';
  let percent = 100;

  const applyRunning = (): void => {
    if (demo === 'lorenz') {
      bounce.enabled = false;
      lorenz.active = true;
      lorenz.enabled = animate;
    } else {
      lorenz.active = false;
      lorenz.enabled = false;
      bounce.enabled = animate;
    }
  };

  return {
    snapshot: () => ({
      visible,
      animate,
      demo,
      percent,
      count: record.count,
      capacity: record.capacity,
      verts: record.count,
      a: lorenz.a,
      b: lorenz.b,
      r: lorenz.r,
      dt: lorenz.dt,
      alpha: lorenz.brightness,
    }),
    invoke(action, args) {
      switch (action) {
        case 'setVisible':
          visible = args[0] === true;
          engine.world.components.Renderable.visible[entity.eid] = visible ? 1 : 0;
          break;
        case 'setPercent':
          percent = clamp(Number(args[0]), 0, 100);
          record.count = Math.round(record.capacity * (percent / 100));
          if (demo === 'lorenz') lorenz.syncDisplay(entity.eid, record);
          break;
        case 'setDemo':
          demo = args[0] === 'bounce' ? 'bounce' : 'lorenz';
          applyRunning();
          if (demo === 'lorenz') {
            lorenz.syncDisplay(entity.eid, record);
            lorenz.setBrightness(lorenz.brightness);
          } else {
            fillRandomCloud(record, 6);
          }
          break;
        case 'setAnimate':
          animate = args[0] === true;
          applyRunning();
          break;
        case 'setParam': {
          // Ignore non-finite input, as the Vue number fields did.
          const value = Number(args[1]);
          if (!Number.isFinite(value)) break;
          if (args[0] === 'a') lorenz.a = value;
          else if (args[0] === 'b') lorenz.b = value;
          else if (args[0] === 'r') lorenz.r = value;
          else if (args[0] === 'dt') lorenz.dt = value;
          else if (args[0] === 'alpha') lorenz.setBrightness(value);
          break;
        }
        case 'reset':
          if (demo === 'lorenz') lorenz.reset();
          else fillRandomCloud(record, 6);
          break;
      }
    },
  };
}

function createHierarchy(engine: GravixEngine, orbit: ParentOrbitSystem): World {
  engine.createCamera({
    name: 'hierarchy-camera',
    fov: Math.PI / 4,
    nearPlane: 0.1,
    farPlane: 200,
    position: [14, 10, 14],
    target: [0, 0, 0],
  });

  const spawnPair = (): { parentEid: number; childEid: number } => {
    const parent = spawnDynamicMesh(engine, 'parent', buildMarker(4, [0.3, 0.75, 1, 1]), MARKER_TOPOLOGY, [0, 0, 0]);
    const child = spawnDynamicMesh(engine, 'child', buildMarker(2, [1, 0.55, 0.2, 1]), MARKER_TOPOLOGY, [6, 0, 0]);
    child.entity.setParent(parent.entity);
    return { parentEid: parent.entity.eid, childEid: child.entity.eid };
  };

  let ids = spawnPair();
  let parentVisible = true;
  let childVisible = true;
  let cycles = 0;
  const { Renderable } = engine.world.components;
  const setVisible = (eid: number, on: boolean): void => {
    if (engine.world.entities.wrap(eid).isValid()) Renderable.visible[eid] = on ? 1 : 0;
  };

  return {
    snapshot: () => ({ parentVisible, childVisible, orbit: orbit.enabled, cycles, verts: 6 }),
    invoke(action, args) {
      switch (action) {
        case 'setParentVisible':
          parentVisible = args[0] === true;
          setVisible(ids.parentEid, parentVisible);
          break;
        case 'setChildVisible':
          childVisible = args[0] === true;
          setVisible(ids.childEid, childVisible);
          break;
        case 'setOrbit':
          orbit.enabled = args[0] === true;
          break;
        case 'recycle': {
          // Destroying the parent takes its child with it; the resource count
          // in the stats line should come back to where it was.
          const parent = engine.world.entities.wrap(ids.parentEid);
          if (parent.isValid()) parent.destroy();
          ids = spawnPair();
          cycles += 1;
          setVisible(ids.parentEid, parentVisible);
          setVisible(ids.childEid, childVisible);
          break;
        }
      }
    },
  };
}

/** `?sim=ws://host:port` connects the traffic world as soon as it starts. */
function trafficAutoConnect(launch: Launch): { url: string; scenario: string; vehicles: number } | null {
  if (!launch.sim) return null;
  const params = queryParams();
  const vehicles = Number(params.get('vehicles') ?? 0);
  return {
    url: launch.sim,
    scenario: params.get('scenario') ?? 'grid-small',
    vehicles: Number.isFinite(vehicles) ? vehicles : 0,
  };
}

// ---------------------------------------------------------------------------
// Mount / state / invoke / dispose.

async function mount(kind: WorldKind, host: HTMLElement, launchJson?: string): Promise<string> {
  dispose(kind);
  const launch = parseLaunch(launchJson);

  // The canvas is absolutely positioned, so the host must be a positioning
  // context. Only add one if it lacks it: world.html's host is already
  // `position: absolute; inset: 0`, and forcing `relative` there collapses it
  // to its (empty) content height -- a 0-pixel-tall canvas and a black view.
  if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
  Object.assign(host.style, { overflow: 'hidden', background: '#000' });
  const canvas = document.createElement('canvas');
  Object.assign(canvas.style, {
    position: 'absolute', inset: '0', width: '100%', height: '100%',
    display: 'block', touchAction: 'none', outline: 'none',
  });
  host.replaceChildren(canvas);

  const entry: Mounted = {
    kind, running: null, world: null, error: null, cancelled: false, teardown: () => {},
  };
  mounted.set(kind, entry);

  // Flutter lays the element out after creating it, so the canvas is 0x0 when
  // the engine starts. Babylon only reads the size when told to: resize on
  // every layout change, or the world draws into an empty buffer.
  const observer = new ResizeObserver(() => {
    entry.running?.backend.resize();
    // One line per layout change: in a WebView this is the only window into
    // sizing problems (Android logcat, WebView2 DevTools).
    console.info(`[gravix] ${kind} canvas ${canvas.clientWidth}x${canvas.clientHeight} ` +
      `buffer ${canvas.width}x${canvas.height} viewport ${window.innerWidth}x${window.innerHeight}`);
  });
  observer.observe(canvas);
  entry.teardown = () => {
    observer.disconnect();
    entry.world?.dispose?.();
    entry.running?.engine.dispose();
    host.replaceChildren();
  };

  // Per-world systems must exist before create(), which seals the scheduler.
  const orbit = new ParentOrbitSystem();
  const bounce = new PointCloudSimulationSystem({ halfExtent: 6, maxSpeed: 1.5 });
  bounce.enabled = false;
  const lorenz = new LorenzAttractorSystem();
  const extra: Pick<GravixEngineOptions, 'clearColor' | 'sceneName' | 'systems'> =
    kind === 'terrain'
      ? { clearColor: [0.04, 0.05, 0.09, 1], sceneName: 'terrain' }
      : kind === 'cloud'
        ? { clearColor: [0, 0, 0, 1], sceneName: 'cloud', systems: [bounce, lorenz] }
        : kind === 'traffic'
          ? { clearColor: [0.03, 0.05, 0.06, 1], sceneName: 'traffic' }
          : { clearColor: [0.06, 0.04, 0.08, 1], sceneName: 'hierarchy', systems: [orbit] };

  try {
    const backend = new BabylonBackend();
    const engine = await GravixEngine.create(backend, {
      canvas,
      preference: launch.backend === 'webgl' ? BackendPreference.WebGL2 : BackendPreference.Auto,
      failDeviceCreation: launch.failDevice,
      ...extra,
    });
    if (entry.cancelled) {
      engine.dispose();
      return 'cancelled';
    }
    entry.running = { engine, backend };
    backend.resize();
    entry.world =
      kind === 'terrain'
        ? createTerrain(engine)
        : kind === 'cloud'
          ? createCloud(engine, launch, bounce, lorenz)
          : kind === 'traffic'
            ? createTraffic(engine, trafficAutoConnect(launch))
            : createHierarchy(engine, orbit);
    engine.start();
    return engine.backendKind;
  } catch (e) {
    entry.error = e instanceof Error ? e.message : String(e);
    console.error(`GravixEngine (${kind}) failed to start`, e);
    throw e;
  }
}

function state(kind: WorldKind): string {
  const entry = mounted.get(kind);
  if (!entry) return JSON.stringify({ mounted: false });
  const running = entry.running;
  const base: Record<string, unknown> = {
    mounted: true,
    ready: running !== null && entry.world !== null,
    error: entry.error,
  };
  if (running && entry.world) {
    const stats = running.engine.getStats();
    Object.assign(base, {
      backend: running.engine.backendKind,
      fps: stats.fps,
      frame: running.engine.world.time.frame,
      resources: running.engine.world.resources.size(),
      ...entry.world.snapshot(),
    });
  }
  return JSON.stringify(base);
}

function invoke(kind: WorldKind, action: string, argsJson = '[]'): void {
  const args = JSON.parse(argsJson) as unknown[];
  mounted.get(kind)?.world?.invoke(action, Array.isArray(args) ? args : []);
}

function dispose(kind: WorldKind): void {
  const entry = mounted.get(kind);
  if (!entry) return;
  entry.cancelled = true;
  entry.teardown();
  mounted.delete(kind);
}

// ---------------------------------------------------------------------------

function clamp(value: number, lo: number, hi: number): number {
  return Number.isFinite(value) ? Math.min(hi, Math.max(lo, value)) : lo;
}

/** gravix-quasar's random cloud for the bouncing-box demo. */
function fillRandomCloud(target: PointCloudRecord, halfExtent: number): void {
  const { positions, colors, capacity } = target;
  const extent = halfExtent * 2;
  for (let i = 0; i < capacity; i++) {
    const p = i * 3;
    positions[p] = Math.random() * extent - halfExtent;
    positions[p + 1] = Math.random() * extent - halfExtent;
    positions[p + 2] = Math.random() * extent - halfExtent;
    const c = i * 4;
    colors[c] = Math.random();
    colors[c + 1] = Math.random();
    colors[c + 2] = Math.random();
    colors[c + 3] = 1;
  }
  target.dirty = true;
  target.revision += 1;
}

(window as unknown as { GravixWorlds: unknown }).GravixWorlds = {
  mount,
  state,
  invoke,
  dispose,
  launchFromUrl,
};
