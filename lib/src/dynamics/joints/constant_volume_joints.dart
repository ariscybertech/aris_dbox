/*******************************************************************************
 * Copyright (c) 2015, Daniel Murphy, Google
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************/

part of box2d;

class ConstantVolumeJoint extends Joint {
  final List<Body> _bodies;
  Float64List _targetLengths;
  double _targetVolume = 0.0;

  List<Vec2> _normals;
  double _m_impulse = 0.0;

  World _world;

  List<DistanceJoint> _distanceJoints;

  List<Body> getBodies() {
    return _bodies;
  }

  List<DistanceJoint> getJoints() {
    return _distanceJoints;
  }

  void inflate(double factor) {
    _targetVolume *= factor;
  }

  ConstantVolumeJoint(World argWorld, ConstantVolumeJointDef def)
      : super(argWorld.getPool(), def),
        _bodies = def.bodies.toList(growable: false) {
    _world = argWorld;
    if (def.bodies.length <= 2) {
      throw "You cannot create a constant volume joint with less than three _bodies.";
    }

    _targetLengths = new Float64List(_bodies.length);
    for (int i = 0; i < _targetLengths.length; ++i) {
      final int next = (i == _targetLengths.length - 1) ? 0 : i + 1;
      double dist = _bodies[i]
          .getWorldCenter()
          .sub(_bodies[next].getWorldCenter())
          .length();
      _targetLengths[i] = dist;
    }
    _targetVolume = getBodyArea();

    if (def.joints != null && def.joints.length != def.bodies.length) {
      throw "Incorrect joint definition.  Joints have to correspond to the _bodies";
    }
    if (def.joints == null) {
      final DistanceJointDef djd = new DistanceJointDef();
      _distanceJoints = new List<DistanceJoint>(_bodies.length);
      for (int i = 0; i < _targetLengths.length; ++i) {
        final int next = (i == _targetLengths.length - 1) ? 0 : i + 1;
        djd.frequencyHz = def.frequencyHz; // 20.0;
        djd.dampingRatio = def.dampingRatio; // 50.0;
        djd.collideConnected = def.collideConnected;
        djd.initialize(_bodies[i], _bodies[next], _bodies[i].getWorldCenter(),
            _bodies[next].getWorldCenter());
        _distanceJoints[i] = _world.createJoint(djd);
      }
    } else {
      _distanceJoints = def.joints.toList();
    }

    _normals = new List<Vec2>(_bodies.length);
    for (int i = 0; i < _normals.length; ++i) {
      _normals[i] = new Vec2.zero();
    }
  }

  void destructor() {
    for (int i = 0; i < _distanceJoints.length; ++i) {
      _world.destroyJoint(_distanceJoints[i]);
    }
  }

  double getBodyArea() {
    double area = 0.0;
    for (int i = 0; i < _bodies.length; ++i) {
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      area += _bodies[i].getWorldCenter().x * _bodies[next].getWorldCenter().y -
          _bodies[next].getWorldCenter().x * _bodies[i].getWorldCenter().y;
    }
    area *= .5;
    return area;
  }

  double getSolverArea(List<Position> positions) {
    double area = 0.0;
    for (int i = 0; i < _bodies.length; ++i) {
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      area += positions[_bodies[i].m_islandIndex].c.x *
              positions[_bodies[next].m_islandIndex].c.y -
          positions[_bodies[next].m_islandIndex].c.x *
              positions[_bodies[i].m_islandIndex].c.y;
    }
    area *= .5;
    return area;
  }

  bool _constrainEdges(List<Position> positions) {
    double perimeter = 0.0;
    for (int i = 0; i < _bodies.length; ++i) {
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      double dx = positions[_bodies[next].m_islandIndex].c.x -
          positions[_bodies[i].m_islandIndex].c.x;
      double dy = positions[_bodies[next].m_islandIndex].c.y -
          positions[_bodies[i].m_islandIndex].c.y;
      double dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < Settings.EPSILON) {
        dist = 1.0;
      }
      _normals[i].x = dy / dist;
      _normals[i].y = -dx / dist;
      perimeter += dist;
    }

    final Vec2 delta = pool.popVec2();

    double deltaArea = _targetVolume - getSolverArea(positions);
    double toExtrude = 0.5 * deltaArea / perimeter; // *relaxationFactor
    // double sumdeltax = 0.0f;
    bool done = true;
    for (int i = 0; i < _bodies.length; ++i) {
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      delta.setXY(toExtrude * (_normals[i].x + _normals[next].x),
          toExtrude * (_normals[i].y + _normals[next].y));
      // sumdeltax += dx;
      double normSqrd = delta.lengthSquared();
      if (normSqrd >
          Settings.maxLinearCorrection * Settings.maxLinearCorrection) {
        delta.mulLocal(Settings.maxLinearCorrection / Math.sqrt(normSqrd));
      }
      if (normSqrd > Settings.linearSlop * Settings.linearSlop) {
        done = false;
      }
      positions[_bodies[next].m_islandIndex].c.x += delta.x;
      positions[_bodies[next].m_islandIndex].c.y += delta.y;
      // _bodies[next].m_linearVelocity.x += delta.x * step.inv_dt;
      // _bodies[next].m_linearVelocity.y += delta.y * step.inv_dt;
    }

    pool.pushVec2(1);
    // System.out.println(sumdeltax);
    return done;
  }

  void initVelocityConstraints(final SolverData step) {
    List<Velocity> velocities = step.velocities;
    List<Position> positions = step.positions;
    final List<Vec2> d = pool.getVec2Array(_bodies.length);

    for (int i = 0; i < _bodies.length; ++i) {
      final int prev = (i == 0) ? _bodies.length - 1 : i - 1;
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      d[i].set(positions[_bodies[next].m_islandIndex].c);
      d[i].subLocal(positions[_bodies[prev].m_islandIndex].c);
    }

    if (step.step.warmStarting) {
      _m_impulse *= step.step.dtRatio;
      // double lambda = -2.0f * crossMassSum / dotMassSum;
      // System.out.println(crossMassSum + " " +dotMassSum);
      // lambda = MathUtils.clamp(lambda, -Settings.maxLinearCorrection,
      // Settings.maxLinearCorrection);
      // _m_impulse = lambda;
      for (int i = 0; i < _bodies.length; ++i) {
        velocities[_bodies[i].m_islandIndex].v.x +=
            _bodies[i].m_invMass * d[i].y * .5 * _m_impulse;
        velocities[_bodies[i].m_islandIndex].v.y +=
            _bodies[i].m_invMass * -d[i].x * .5 * _m_impulse;
      }
    } else {
      _m_impulse = 0.0;
    }
  }

  bool solvePositionConstraints(SolverData step) {
    return _constrainEdges(step.positions);
  }

  void solveVelocityConstraints(final SolverData step) {
    double crossMassSum = 0.0;
    double dotMassSum = 0.0;

    List<Velocity> velocities = step.velocities;
    List<Position> positions = step.positions;
    final List<Vec2> d = pool.getVec2Array(_bodies.length);

    for (int i = 0; i < _bodies.length; ++i) {
      final int prev = (i == 0) ? _bodies.length - 1 : i - 1;
      final int next = (i == _bodies.length - 1) ? 0 : i + 1;
      d[i].set(positions[_bodies[next].m_islandIndex].c);
      d[i].subLocal(positions[_bodies[prev].m_islandIndex].c);
      dotMassSum += (d[i].lengthSquared()) / _bodies[i].getMass();
      crossMassSum += Vec2.cross(velocities[_bodies[i].m_islandIndex].v, d[i]);
    }
    double lambda = -2.0 * crossMassSum / dotMassSum;
    // System.out.println(crossMassSum + " " +dotMassSum);
    // lambda = MathUtils.clamp(lambda, -Settings.maxLinearCorrection,
    // Settings.maxLinearCorrection);
    _m_impulse += lambda;
    // System.out.println(_m_impulse);
    for (int i = 0; i < _bodies.length; ++i) {
      velocities[_bodies[i].m_islandIndex].v.x +=
          _bodies[i].m_invMass * d[i].y * .5 * lambda;
      velocities[_bodies[i].m_islandIndex].v.y +=
          _bodies[i].m_invMass * -d[i].x * .5 * lambda;
    }
  }

  /** No-op */
  void getAnchorA(Vec2 argOut) {}

  /** No-op */
  void getAnchorB(Vec2 argOut) {}

  /** No-op */
  void getReactionForce(double inv_dt, Vec2 argOut) {}

  /** No-op */
  double getReactionTorque(double inv_dt) {
    return 0.0;
  }
}
