"""Bounded mouse-water field for the decorative shader, independent of inference.

Ports WaterTrail from the supplied HTML. Vectorized fixed-size arrays avoid Python
pixel loops; the timer sleeps once the retained trail has completely dissipated.
"""
from __future__ import annotations

import math
import threading
import time
import uuid
from collections import deque

import numpy as np
from PySide6.QtCore import QObject, Property, QPointF, QSize, QTimer, Signal
from PySide6.QtGui import QImage
from PySide6.QtQml import QmlElement
from PySide6.QtQuick import QQuickImageProvider

QML_IMPORT_NAME = "Icing.Ambient"
QML_IMPORT_MAJOR_VERSION = 1
_images: dict[str, QImage] = {}
_lock = threading.Lock()


def _release_image(key):
    with _lock:
        _images.pop(key, None)


class WaterImageProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)

    def requestImage(self, identifier: str, size: QSize, requestedSize: QSize):
        with _lock:
            image = _images.get(identifier.split('?')[0], QImage()).copy()
        size.setWidth(image.width())
        size.setHeight(image.height())
        return image


@QmlElement
class WaterField(QObject):
    changed = Signal()
    activityChanged = Signal()
    imageChanged = Signal()
    W, H = 288, 208
    PADDING = .45
    RADIUS, RESPONSE, PERSISTENCE = .60, 2.5, 6.

    def __init__(self, parent=None):
        super().__init__(parent)
        self._key = uuid.uuid4().hex
        self._revision = 0
        self.destroyed.connect(lambda _=None, key=self._key: _release_image(key))
        self._running = self._inside = self._active = False
        self._x = self._y = .5
        self._aspect = 1.6
        self._quiet = self._time = self._envelope = 0.
        self._previous = 0.
        self._accumulator = 0.
        self._pointer_time = 0.
        self._just_entered = True
        self._segments = deque(maxlen=64)
        self._density, self._vortex, self._wave, self._prev = [np.zeros((self.H, self.W), np.float32) for _ in range(4)]
        self._pixels = np.zeros((self.H, self.W, 4), np.uint8)
        self._image = QImage()
        self._configure()
        self._pack()
        self._timer = QTimer(self)
        self._timer.setInterval(33)
        self._timer.timeout.connect(self._advance)

    source = Property(str, lambda self: f'image://ambient/{self._key}?v={self._revision}', notify=imageChanged)

    def _configure(self):
        self._world_w, self._world_h = self._aspect + .9, 1.9
        self._gx = ((np.arange(self.W, dtype=np.float32) + .5) / self.W * self._world_w - self.PADDING)[None, :]
        self._gy = ((np.arange(self.H, dtype=np.float32) + .5) / self.H * self._world_h - self.PADDING)[:, None]
        distance = np.minimum(np.minimum(self._gx + .45, self._world_w - self._gx - .45),
                              np.minimum(self._gy + .45, self._world_h - self._gy - .45))
        t = np.clip(1 - distance / .15, 0, 1)
        self._sponge = t*t*(3-2*t)

    def _wake(self):
        if self._running and (self._inside or self._active) and not self._timer.isActive():
            self._previous = time.monotonic()
            self._accumulator = 0.
            self._timer.start()

    def _set_running(self, value):
        if self._running == value:
            return
        self._running = value
        if not value:
            self._timer.stop()
            self._reset()
        self._wake()
        self.changed.emit()

    running = Property(bool, lambda self: self._running, _set_running, notify=changed)

    def _set_inside(self, value):
        if self._inside != value:
            self._inside = value
            self._just_entered = value
            self._quiet = 0.
            self._wake()
            self.changed.emit()

    pointerInside = Property(bool, lambda self: self._inside, _set_inside, notify=changed)

    def _set_coordinate(self, axis, value):
        self._set_position(QPointF(value if axis == '_x' else self._x, value if axis == '_y' else self._y))

    def _set_position(self, value):
        x, y = max(0., min(1., value.x())), max(0., min(1., value.y()))
        if (x, y) == (self._x, self._y):
            return
        now = time.monotonic()
        duration = max(.004, min(.06, now-self._pointer_time))
        if self._inside:
            x0, y0 = (x, y) if self._just_entered else (self._x, self._y)
            self._segments.append((x0, y0, x, y, duration))
        self._x, self._y, self._pointer_time = x, y, now
        self._just_entered = False
        self.changed.emit()

    pointerPosition = Property(QPointF, lambda self: QPointF(self._x, self._y), _set_position, notify=changed)

    pointerX = Property(float, lambda self: self._x, lambda self, v: self._set_coordinate('_x', v), notify=changed)
    pointerY = Property(float, lambda self: self._y, lambda self, v: self._set_coordinate('_y', v), notify=changed)

    def _set_aspect(self, value):
        value = max(.1, value)
        if abs(value-self._aspect) > 1e-6:
            self._aspect = value
            self._configure()
            self._reset()
            self.changed.emit()

    aspect = Property(float, lambda self: self._aspect, _set_aspect, notify=changed)
    activity = Property(float, lambda self: float(self._active), notify=activityChanged)
    envelope = Property(float, lambda self: self._envelope, notify=activityChanged)

    def _reset(self):
        for field in (self._density, self._vortex, self._wave, self._prev):
            field.fill(0)
        self._segments.clear()
        self._active = False
        self._time = self._envelope = 0.
        self._pack()
        self.activityChanged.emit()

    def _stamp(self, x0, y0, x1, y1, dose):
        ax, bx = x0*self._aspect, x1*self._aspect
        dx, dy = bx-ax, y1-y0
        px, py = self._gx-ax, self._gy-y0
        length2 = dx*dx+dy*dy
        t = np.clip((px*dx+py*dy)/length2, 0, 1) if length2 > 1e-10 else 0.
        sigma = .055+self.RADIUS*.16
        weight = np.exp(-((px-dx*t)**2+(py-dy*t)**2)/(sigma*sigma))
        self._density[:] = 1-(1-self._density)*np.exp(-dose*weight)

    def _advance(self):
        now = time.monotonic()
        self._accumulator = min(.10, self._accumulator+now-self._previous)
        self._previous = now
        changed = False
        while self._accumulator >= 1/30:
            self._accumulator -= 1/30
            self._step(1/30)
            changed = True
        if changed:
            self._pack()
            self.activityChanged.emit()
        if not self._inside and not self._active:
            self._timer.stop()

    def _step(self, dt):
        if not self._inside and not self._active:
            return
        self._active = True
        self._time += dt
        self._quiet = 0. if self._inside else self._quiet+dt
        if self._quiet >= self.PERSISTENCE+5:
            self._reset()
            return
        for _ in range(min(8, len(self._segments))):
            x0, y0, x1, y1, duration = self._segments.popleft()
            length = math.hypot((x1-x0)*self._aspect, y1-y0)
            self._stamp(x0, y0, x1, y1, duration*2.6+length*.8)
        if self._inside:
            self._stamp(self._x, self._y, self._x, self._y, dt*2.2)
        absorption = 1/(1+dt*12*self._sponge)
        self._density *= math.exp(-dt/(self.PERSISTENCE/3))*absorption
        old = self._vortex.copy()
        rate = np.where(self._density > old, 1-math.exp(-dt/self.RESPONSE), 1-math.exp(-dt/2.7))
        self._vortex[:] = (old+(self._density-old)*rate)*absorption
        z, prev = self._wave, self._prev
        core = z[1:-1, 1:-1]
        lx = min(.24, (.095*dt*self.W/self._world_w)**2)
        ly = min(.24, (.095*dt*self.H/self._world_h)**2)
        next_wave = np.zeros_like(z)
        next_wave[1:-1, 1:-1] = np.clip((core+(core-prev[1:-1, 1:-1])*.974
            +lx*(z[1:-1, :-2]+z[1:-1, 2:]-2*core)+ly*(z[:-2, 1:-1]+z[2:, 1:-1]-2*core)
            -core*.0015+self._vortex[1:-1, 1:-1]*math.sin(self._time*1.15)*.0012
            +(self._vortex-old)[1:-1, 1:-1]*.010)*absorption[1:-1, 1:-1], -.65, .65)
        self._prev, self._wave = z, next_wave
        a = max(0., min(1., (self._quiet-self.PERSISTENCE)/5))
        self._envelope = 1-a*a*(3-2*a)

    def _pack(self):
        vortex = np.rint(np.clip(self._vortex, 0, 1)*65535).astype(np.uint16)
        wave = np.rint((np.clip(self._wave, -1, 1)*.5+.5)*65535).astype(np.uint16)
        # Opaque RGB survives Qt's premultiplied texture pipeline: density R, wave GB.
        self._pixels[:, :, 0] = vortex >> 8
        self._pixels[:, :, 1], self._pixels[:, :, 2] = wave >> 8, wave & 255
        self._pixels[:, :, 3] = 255
        self._image = QImage(self._pixels.data, self.W, self.H, self.W*4, QImage.Format.Format_RGBA8888).copy()
        with _lock:
            _images[self._key] = self._image
        self._revision += 1
        self.imageChanged.emit()
