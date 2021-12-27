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

/**
 * Java-specific class for returning edge results
 */
class _EdgeResults {
  double separation = 0.0;
  int edgeIndex = 0;
}

/**
 * Used for computing contact manifolds.
 */
class ClipVertex {
  final Vec2 v = new Vec2.zero();
  final ContactID id = new ContactID();

  void set(final ClipVertex cv) {
    Vec2 v1 = cv.v;
    v.x = v1.x;
    v.y = v1.y;
    ContactID c = cv.id;
    id.indexA = c.indexA;
    id.indexB = c.indexB;
    id.typeA = c.typeA;
    id.typeB = c.typeB;
  }
}

/**
 * This is used for determining the state of contact points.
 * 
 * @author Daniel Murphy
 */
enum PointState {
  /**
   * point does not exist
   */
  NULL_STATE,
  /**
   * point was added in the update
   */
  ADD_STATE,
  /**
   * point persisted across the update
   */
  PERSIST_STATE,
  /**
   * point was removed in the update
   */
  REMOVE_STATE
}

/**
 * This structure is used to keep track of the best separating axis.
 */

enum EPAxisType { UNKNOWN, EDGE_A, EDGE_B }

class EPAxis {
  EPAxisType type = EPAxisType.UNKNOWN;
  int index = 0;
  double separation = 0.0;
}

/**
 * This holds polygon B expressed in frame A.
 */
class TempPolygon {
  final List<Vec2> vertices = new List<Vec2>(Settings.maxPolygonVertices);
  final List<Vec2> normals = new List<Vec2>(Settings.maxPolygonVertices);
  int count = 0;

  TempPolygon() {
    for (int i = 0; i < vertices.length; i++) {
      vertices[i] = new Vec2.zero();
      normals[i] = new Vec2.zero();
    }
  }
}

/**
 * Reference face used for clipping
 */
class _ReferenceFace {
  int i1 = 0,
      i2 = 0;
  final Vec2 v1 = new Vec2.zero();
  final Vec2 v2 = new Vec2.zero();
  final Vec2 normal = new Vec2.zero();

  final Vec2 sideNormal1 = new Vec2.zero();
  double sideOffset1 = 0.0;

  final Vec2 sideNormal2 = new Vec2.zero();
  double sideOffset2 = 0.0;
}

/**
 * Functions used for computing contact points, distance queries, and TOI queries. Collision methods
 * are non-static for pooling speed, retrieve a collision object from the {@link SingletonPool}.
 * Should not be finalructed.
 */
class Collision {
  static const int NULL_FEATURE = 0x3FFFFFFF; // Integer.MAX_VALUE;

  final IWorldPool _pool;

  Collision(this._pool) {
    _incidentEdge[0] = new ClipVertex();
    _incidentEdge[1] = new ClipVertex();
    _clipPoints1[0] = new ClipVertex();
    _clipPoints1[1] = new ClipVertex();
    _clipPoints2[0] = new ClipVertex();
    _clipPoints2[1] = new ClipVertex();
  }

  final DistanceInput _input = new DistanceInput();
  final SimplexCache _cache = new SimplexCache();
  final DistanceOutput _output = new DistanceOutput();

  /**
   * Determine if two generic shapes overlap.
   * 
   * @param shapeA
   * @param shapeB
   * @param xfA
   * @param xfB
   * @return
   */
  bool testOverlap(Shape shapeA, int indexA, Shape shapeB, int indexB,
      Transform xfA, Transform xfB) {
    _input.proxyA.set(shapeA, indexA);
    _input.proxyB.set(shapeB, indexB);
    _input.transformA.set(xfA);
    _input.transformB.set(xfB);
    _input.useRadii = true;

    _cache.count = 0;

    _pool.getDistance().distance(_output, _cache, _input);
    // djm note: anything significant about 10.0f?
    return _output.distance < 10.0 * Settings.EPSILON;
  }

  /**
   * Compute the point states given two manifolds. The states pertain to the transition from
   * manifold1 to manifold2. So state1 is either persist or remove while state2 is either add or
   * persist.
   * 
   * @param state1
   * @param state2
   * @param manifold1
   * @param manifold2
   */
  static void getPointStates(final List<PointState> state1,
      final List<PointState> state2, final Manifold manifold1,
      final Manifold manifold2) {
    for (int i = 0; i < Settings.maxManifoldPoints; i++) {
      state1[i] = PointState.NULL_STATE;
      state2[i] = PointState.NULL_STATE;
    }

    // Detect persists and removes.
    for (int i = 0; i < manifold1.pointCount; i++) {
      ContactID id = manifold1.points[i].id;

      state1[i] = PointState.REMOVE_STATE;

      for (int j = 0; j < manifold2.pointCount; j++) {
        if (manifold2.points[j].id.isEqual(id)) {
          state1[i] = PointState.PERSIST_STATE;
          break;
        }
      }
    }

    // Detect persists and adds
    for (int i = 0; i < manifold2.pointCount; i++) {
      ContactID id = manifold2.points[i].id;

      state2[i] = PointState.ADD_STATE;

      for (int j = 0; j < manifold1.pointCount; j++) {
        if (manifold1.points[j].id.isEqual(id)) {
          state2[i] = PointState.PERSIST_STATE;
          break;
        }
      }
    }
  }

  /**
   * Clipping for contact manifolds. Sutherland-Hodgman clipping.
   * 
   * @param vOut
   * @param vIn
   * @param normal
   * @param offset
   * @return
   */
  static int clipSegmentToLine(final List<ClipVertex> vOut,
      final List<ClipVertex> vIn, final Vec2 normal, double offset,
      int vertexIndexA) {

    // Start with no _output points
    int numOut = 0;
    final ClipVertex vIn0 = vIn[0];
    final ClipVertex vIn1 = vIn[1];
    final Vec2 vIn0v = vIn0.v;
    final Vec2 vIn1v = vIn1.v;

    // Calculate the distance of end points to the line
    double distance0 = Vec2.dot(normal, vIn0v) - offset;
    double distance1 = Vec2.dot(normal, vIn1v) - offset;

    // If the points are behind the plane
    if (distance0 <= 0.0) {
      vOut[numOut++].set(vIn0);
    }
    if (distance1 <= 0.0) {
      vOut[numOut++].set(vIn1);
    }

    // If the points are on different sides of the plane
    if (distance0 * distance1 < 0.0) {
      // Find intersection point of edge and plane
      double interp = distance0 / (distance0 - distance1);

      ClipVertex vOutNO = vOut[numOut];
      // vOut[numOut].v = vIn[0].v + interp * (vIn[1].v - vIn[0].v);
      vOutNO.v.x = vIn0v.x + interp * (vIn1v.x - vIn0v.x);
      vOutNO.v.y = vIn0v.y + interp * (vIn1v.y - vIn0v.y);

      // VertexA is hitting edgeB.
      vOutNO.id.indexA = vertexIndexA & 0xFF;
      vOutNO.id.indexB = vIn0.id.indexB;
      vOutNO.id.typeA = ContactIDType.VERTEX.index & 0xFF;
      vOutNO.id.typeB = ContactIDType.FACE.index & 0xFF;
      ++numOut;
    }

    return numOut;
  }

  // #### COLLISION STUFF (not from collision.h or collision.cpp) ####

  // djm pooling
  static Vec2 _d = new Vec2.zero();

  /**
   * Compute the collision manifold between two circles.
   * 
   * @param manifold
   * @param circle1
   * @param xfA
   * @param circle2
   * @param xfB
   */
  void collideCircles(Manifold manifold, final CircleShape circle1,
      final Transform xfA, final CircleShape circle2, final Transform xfB) {
    manifold.pointCount = 0;
    // before inline:
    // Transform.mulToOut(xfA, circle1.m_p, pA);
    // Transform.mulToOut(xfB, circle2.m_p, pB);
    // d.set(pB).subLocal(pA);
    // double distSqr = d.x * d.x + d.y * d.y;

    // after inline:
    Vec2 circle1p = circle1.m_p;
    Vec2 circle2p = circle2.m_p;
    double pAx = (xfA.q.c * circle1p.x - xfA.q.s * circle1p.y) + xfA.p.x;
    double pAy = (xfA.q.s * circle1p.x + xfA.q.c * circle1p.y) + xfA.p.y;
    double pBx = (xfB.q.c * circle2p.x - xfB.q.s * circle2p.y) + xfB.p.x;
    double pBy = (xfB.q.s * circle2p.x + xfB.q.c * circle2p.y) + xfB.p.y;
    double dx = pBx - pAx;
    double dy = pBy - pAy;
    double distSqr = dx * dx + dy * dy;
    // end inline

    final double radius = circle1.m_radius + circle2.m_radius;
    if (distSqr > radius * radius) {
      return;
    }

    manifold.type = ManifoldType.CIRCLES;
    manifold.localPoint.set(circle1p);
    manifold.localNormal.setZero();
    manifold.pointCount = 1;

    manifold.points[0].localPoint.set(circle2p);
    manifold.points[0].id.zero();
  }

  // djm pooling, and from above

  /**
   * Compute the collision manifold between a polygon and a circle.
   * 
   * @param manifold
   * @param polygon
   * @param xfA
   * @param circle
   * @param xfB
   */
  void collidePolygonAndCircle(Manifold manifold, final PolygonShape polygon,
      final Transform xfA, final CircleShape circle, final Transform xfB) {
    manifold.pointCount = 0;
    // Vec2 v = circle.m_p;

    // Compute circle position in the frame of the polygon.
    // before inline:
    // Transform.mulToOutUnsafe(xfB, circle.m_p, c);
    // Transform.mulTransToOut(xfA, c, cLocal);
    // final double cLocalx = cLocal.x;
    // final double cLocaly = cLocal.y;
    // after inline:
    final Vec2 circlep = circle.m_p;
    final Rot xfBq = xfB.q;
    final Rot xfAq = xfA.q;
    final double cx = (xfBq.c * circlep.x - xfBq.s * circlep.y) + xfB.p.x;
    final double cy = (xfBq.s * circlep.x + xfBq.c * circlep.y) + xfB.p.y;
    final double px = cx - xfA.p.x;
    final double py = cy - xfA.p.y;
    final double cLocalx = (xfAq.c * px + xfAq.s * py);
    final double cLocaly = (-xfAq.s * px + xfAq.c * py);
    // end inline

    // Find the min separating edge.
    int normalIndex = 0;
    double separation = -double.MAX_FINITE;
    final double radius = polygon.m_radius + circle.m_radius;
    final int vertexCount = polygon.m_count;
    double s;
    final List<Vec2> vertices = polygon.m_vertices;
    final List<Vec2> normals = polygon.m_normals;

    for (int i = 0; i < vertexCount; i++) {
      // before inline
      // temp.set(cLocal).subLocal(vertices[i]);
      // double s = Vec2.dot(normals[i], temp);
      // after inline
      final Vec2 vertex = vertices[i];
      final double tempx = cLocalx - vertex.x;
      final double tempy = cLocaly - vertex.y;
      s = normals[i].x * tempx + normals[i].y * tempy;

      if (s > radius) {
        // early out
        return;
      }

      if (s > separation) {
        separation = s;
        normalIndex = i;
      }
    }

    // Vertices that subtend the incident face.
    final int vertIndex1 = normalIndex;
    final int vertIndex2 = vertIndex1 + 1 < vertexCount ? vertIndex1 + 1 : 0;
    final Vec2 v1 = vertices[vertIndex1];
    final Vec2 v2 = vertices[vertIndex2];

    // If the center is inside the polygon ...
    if (separation < Settings.EPSILON) {
      manifold.pointCount = 1;
      manifold.type = ManifoldType.FACE_A;

      // before inline:
      // manifold._localNormal.set(normals[normalIndex]);
      // manifold.localPoint.set(v1).addLocal(v2).mulLocal(.5f);
      // manifold.points[0].localPoint.set(circle.m_p);
      // after inline:
      final Vec2 normal = normals[normalIndex];
      manifold.localNormal.x = normal.x;
      manifold.localNormal.y = normal.y;
      manifold.localPoint.x = (v1.x + v2.x) * .5;
      manifold.localPoint.y = (v1.y + v2.y) * .5;
      final ManifoldPoint mpoint = manifold.points[0];
      mpoint.localPoint.x = circlep.x;
      mpoint.localPoint.y = circlep.y;
      mpoint.id.zero();
      // end inline

      return;
    }

    // Compute barycentric coordinates
    // before inline:
    // temp.set(cLocal).subLocal(v1);
    // temp2.set(v2).subLocal(v1);
    // double u1 = Vec2.dot(temp, temp2);
    // temp.set(cLocal).subLocal(v2);
    // temp2.set(v1).subLocal(v2);
    // double u2 = Vec2.dot(temp, temp2);
    // after inline:
    final double tempX = cLocalx - v1.x;
    final double tempY = cLocaly - v1.y;
    final double temp2X = v2.x - v1.x;
    final double temp2Y = v2.y - v1.y;
    final double u1 = tempX * temp2X + tempY * temp2Y;

    final double temp3X = cLocalx - v2.x;
    final double temp3Y = cLocaly - v2.y;
    final double temp4X = v1.x - v2.x;
    final double temp4Y = v1.y - v2.y;
    final double u2 = temp3X * temp4X + temp3Y * temp4Y;
    // end inline

    if (u1 <= 0.0) {
      // inlined
      final double dx = cLocalx - v1.x;
      final double dy = cLocaly - v1.y;
      if (dx * dx + dy * dy > radius * radius) {
        return;
      }

      manifold.pointCount = 1;
      manifold.type = ManifoldType.FACE_A;
      // before inline:
      // manifold._localNormal.set(cLocal).subLocal(v1);
      // after inline:
      manifold.localNormal.x = cLocalx - v1.x;
      manifold.localNormal.y = cLocaly - v1.y;
      // end inline
      manifold.localNormal.normalize();
      manifold.localPoint.set(v1);
      manifold.points[0].localPoint.set(circlep);
      manifold.points[0].id.zero();
    } else if (u2 <= 0.0) {
      // inlined
      final double dx = cLocalx - v2.x;
      final double dy = cLocaly - v2.y;
      if (dx * dx + dy * dy > radius * radius) {
        return;
      }

      manifold.pointCount = 1;
      manifold.type = ManifoldType.FACE_A;
      // before inline:
      // manifold._localNormal.set(cLocal).subLocal(v2);
      // after inline:
      manifold.localNormal.x = cLocalx - v2.x;
      manifold.localNormal.y = cLocaly - v2.y;
      // end inline
      manifold.localNormal.normalize();
      manifold.localPoint.set(v2);
      manifold.points[0].localPoint.set(circlep);
      manifold.points[0].id.zero();
    } else {
      // Vec2 faceCenter = 0.5f * (v1 + v2);
      // (temp is faceCenter)
      // before inline:
      // temp.set(v1).addLocal(v2).mulLocal(.5f);
      //
      // temp2.set(cLocal).subLocal(temp);
      // separation = Vec2.dot(temp2, normals[vertIndex1]);
      // if (separation > radius) {
      // return;
      // }
      // after inline:
      final double fcx = (v1.x + v2.x) * .5;
      final double fcy = (v1.y + v2.y) * .5;

      final double tx = cLocalx - fcx;
      final double ty = cLocaly - fcy;
      final Vec2 normal = normals[vertIndex1];
      separation = tx * normal.x + ty * normal.y;
      if (separation > radius) {
        return;
      }
      // end inline

      manifold.pointCount = 1;
      manifold.type = ManifoldType.FACE_A;
      manifold.localNormal.set(normals[vertIndex1]);
      manifold.localPoint.x = fcx; // (faceCenter)
      manifold.localPoint.y = fcy;
      manifold.points[0].localPoint.set(circlep);
      manifold.points[0].id.zero();
    }
  }

  // djm pooling, and from above
  final Vec2 _temp = new Vec2.zero();
  final Transform _xf = new Transform.zero();
  final Vec2 _n = new Vec2.zero();
  final Vec2 _v1 = new Vec2.zero();

  /**
   * Find the max separation between poly1 and poly2 using edge normals from poly1.
   * 
   * @param edgeIndex
   * @param poly1
   * @param xf1
   * @param poly2
   * @param xf2
   * @return
   */
  void findMaxSeparation(_EdgeResults results, final PolygonShape poly1,
      final Transform xf1, final PolygonShape poly2, final Transform xf2) {
    int count1 = poly1.m_count;
    int count2 = poly2.m_count;
    List<Vec2> n1s = poly1.m_normals;
    List<Vec2> v1s = poly1.m_vertices;
    List<Vec2> v2s = poly2.m_vertices;

    Transform.mulTransToOutUnsafe(xf2, xf1, _xf);
    final Rot xfq = _xf.q;

    int bestIndex = 0;
    double maxSeparation = -double.MAX_FINITE;
    for (int i = 0; i < count1; i++) {
      // Get poly1 normal in frame2.
      Rot.mulToOutUnsafe(xfq, n1s[i], _n);
      Transform.mulToOutUnsafeVec2(_xf, v1s[i], _v1);

      // Find deepest point for normal i.
      double si = double.MAX_FINITE;
      for (int j = 0; j < count2; ++j) {
        Vec2 v2sj = v2s[j];
        double sij = _n.x * (v2sj.x - _v1.x) + _n.y * (v2sj.y - _v1.y);
        if (sij < si) {
          si = sij;
        }
      }

      if (si > maxSeparation) {
        maxSeparation = si;
        bestIndex = i;
      }
    }

    results.edgeIndex = bestIndex;
    results.separation = maxSeparation;
  }

  void findIncidentEdge(final List<ClipVertex> c, final PolygonShape poly1,
      final Transform xf1, int edge1, final PolygonShape poly2,
      final Transform xf2) {
    int count1 = poly1.m_count;
    final List<Vec2> normals1 = poly1.m_normals;

    int count2 = poly2.m_count;
    final List<Vec2> vertices2 = poly2.m_vertices;
    final List<Vec2> normals2 = poly2.m_normals;

    assert(0 <= edge1 && edge1 < count1);

    final ClipVertex c0 = c[0];
    final ClipVertex c1 = c[1];
    final Rot xf1q = xf1.q;
    final Rot xf2q = xf2.q;

    // Get the normal of the reference edge in poly2's frame.
    // Vec2 normal1 = MulT(xf2.R, Mul(xf1.R, normals1[edge1]));
    // before inline:
    // Rot.mulToOutUnsafe(xf1.q, normals1[edge1], normal1); // temporary
    // Rot.mulTrans(xf2.q, normal1, normal1);
    // after inline:
    final Vec2 v = normals1[edge1];
    final double tempx = xf1q.c * v.x - xf1q.s * v.y;
    final double tempy = xf1q.s * v.x + xf1q.c * v.y;
    final double normal1x = xf2q.c * tempx + xf2q.s * tempy;
    final double normal1y = -xf2q.s * tempx + xf2q.c * tempy;

    // end inline

    // Find the incident edge on poly2.
    int index = 0;
    double minDot = double.MAX_FINITE;
    for (int i = 0; i < count2; ++i) {
      Vec2 b = normals2[i];
      double dot = normal1x * b.x + normal1y * b.y;
      if (dot < minDot) {
        minDot = dot;
        index = i;
      }
    }

    // Build the clip vertices for the incident edge.
    int i1 = index;
    int i2 = i1 + 1 < count2 ? i1 + 1 : 0;

    // c0.v = Mul(xf2, vertices2[i1]);
    Vec2 v1 = vertices2[i1];
    Vec2 out = c0.v;
    out.x = (xf2q.c * v1.x - xf2q.s * v1.y) + xf2.p.x;
    out.y = (xf2q.s * v1.x + xf2q.c * v1.y) + xf2.p.y;
    c0.id.indexA = edge1 & 0xFF;
    c0.id.indexB = i1 & 0xFF;
    c0.id.typeA = ContactIDType.FACE.index & 0xFF;
    c0.id.typeB = ContactIDType.VERTEX.index & 0xFF;

    // c1.v = Mul(xf2, vertices2[i2]);
    Vec2 v2 = vertices2[i2];
    Vec2 out1 = c1.v;
    out1.x = (xf2q.c * v2.x - xf2q.s * v2.y) + xf2.p.x;
    out1.y = (xf2q.s * v2.x + xf2q.c * v2.y) + xf2.p.y;
    c1.id.indexA = edge1 & 0xFF;
    c1.id.indexB = i2 & 0xFF;
    c1.id.typeA = ContactIDType.FACE.index & 0xFF;
    c1.id.typeB = ContactIDType.VERTEX.index & 0xFF;
  }

  final _EdgeResults _results1 = new _EdgeResults();
  final _EdgeResults results2 = new _EdgeResults();
  final List<ClipVertex> _incidentEdge = new List<ClipVertex>(2);
  final Vec2 _localTangent = new Vec2.zero();
  final Vec2 _localNormal = new Vec2.zero();
  final Vec2 _planePoint = new Vec2.zero();
  final Vec2 _tangent = new Vec2.zero();
  final Vec2 _v11 = new Vec2.zero();
  final Vec2 _v12 = new Vec2.zero();
  final List<ClipVertex> _clipPoints1 = new List<ClipVertex>(2);
  final List<ClipVertex> _clipPoints2 = new List<ClipVertex>(2);

  /**
   * Compute the collision manifold between two polygons.
   * 
   * @param manifold
   * @param polygon1
   * @param xf1
   * @param polygon2
   * @param xf2
   */
  void collidePolygons(Manifold manifold, final PolygonShape polyA,
      final Transform xfA, final PolygonShape polyB, final Transform xfB) {
    // Find edge normal of max separation on A - return if separating axis is found
    // Find edge normal of max separation on B - return if separation axis is found
    // Choose reference edge as min(minA, minB)
    // Find incident edge
    // Clip

    // The normal points from 1 to 2

    manifold.pointCount = 0;
    double totalRadius = polyA.m_radius + polyB.m_radius;

    findMaxSeparation(_results1, polyA, xfA, polyB, xfB);
    if (_results1.separation > totalRadius) {
      return;
    }

    findMaxSeparation(results2, polyB, xfB, polyA, xfA);
    if (results2.separation > totalRadius) {
      return;
    }

    PolygonShape poly1; // reference polygon
    PolygonShape poly2; // incident polygon
    Transform xf1, xf2;
    int edge1; // reference edge
    bool flip;
    final double k_tol = 0.1 * Settings.linearSlop;

    if (results2.separation > _results1.separation + k_tol) {
      poly1 = polyB;
      poly2 = polyA;
      xf1 = xfB;
      xf2 = xfA;
      edge1 = results2.edgeIndex;
      manifold.type = ManifoldType.FACE_B;
      flip = true;
    } else {
      poly1 = polyA;
      poly2 = polyB;
      xf1 = xfA;
      xf2 = xfB;
      edge1 = _results1.edgeIndex;
      manifold.type = ManifoldType.FACE_A;
      flip = false;
    }
    final Rot xf1q = xf1.q;

    findIncidentEdge(_incidentEdge, poly1, xf1, edge1, poly2, xf2);

    int count1 = poly1.m_count;
    final List<Vec2> vertices1 = poly1.m_vertices;

    final int iv1 = edge1;
    final int iv2 = edge1 + 1 < count1 ? edge1 + 1 : 0;
    _v11.set(vertices1[iv1]);
    _v12.set(vertices1[iv2]);
    _localTangent.x = _v12.x - _v11.x;
    _localTangent.y = _v12.y - _v11.y;
    _localTangent.normalize();

    // Vec2 _localNormal = Vec2.cross(dv, 1.0f);
    _localNormal.x = 1.0 * _localTangent.y;
    _localNormal.y = -1.0 * _localTangent.x;

    // Vec2 _planePoint = 0.5f * (_v11+ _v12);
    _planePoint.x = (_v11.x + _v12.x) * .5;
    _planePoint.y = (_v11.y + _v12.y) * .5;

    // Rot.mulToOutUnsafe(xf1.q, _localTangent, _tangent);
    _tangent.x = xf1q.c * _localTangent.x - xf1q.s * _localTangent.y;
    _tangent.y = xf1q.s * _localTangent.x + xf1q.c * _localTangent.y;

    // Vec2.crossToOutUnsafe(_tangent, 1f, normal);
    final double normalx = 1.0 * _tangent.y;
    final double normaly = -1.0 * _tangent.x;

    Transform.mulToOutVec2(xf1, _v11, _v11);
    Transform.mulToOutVec2(xf1, _v12, _v12);
    // _v11 = Mul(xf1, _v11);
    // _v12 = Mul(xf1, _v12);

    // Face offset
    // double frontOffset = Vec2.dot(normal, _v11);
    double frontOffset = normalx * _v11.x + normaly * _v11.y;

    // Side offsets, extended by polytope skin thickness.
    // double sideOffset1 = -Vec2.dot(_tangent, _v11) + totalRadius;
    // double sideOffset2 = Vec2.dot(_tangent, _v12) + totalRadius;
    double sideOffset1 =
        -(_tangent.x * _v11.x + _tangent.y * _v11.y) + totalRadius;
    double sideOffset2 =
        _tangent.x * _v12.x + _tangent.y * _v12.y + totalRadius;

    // Clip incident edge against extruded edge1 side edges.
    // ClipVertex _clipPoints1[2];
    // ClipVertex _clipPoints2[2];
    int np;

    // Clip to box side 1
    // np = ClipSegmentToLine(_clipPoints1, _incidentEdge, -sideNormal, sideOffset1);
    _tangent.negateLocal();
    np = clipSegmentToLine(
        _clipPoints1, _incidentEdge, _tangent, sideOffset1, iv1);
    _tangent.negateLocal();

    if (np < 2) {
      return;
    }

    // Clip to negative box side 1
    np = clipSegmentToLine(
        _clipPoints2, _clipPoints1, _tangent, sideOffset2, iv2);

    if (np < 2) {
      return;
    }

    // Now _clipPoints2 contains the clipped points.
    manifold.localNormal.set(_localNormal);
    manifold.localPoint.set(_planePoint);

    int pointCount = 0;
    for (int i = 0; i < Settings.maxManifoldPoints; ++i) {
      // double separation = Vec2.dot(normal, _clipPoints2[i].v) - frontOffset;
      double separation = normalx * _clipPoints2[i].v.x +
          normaly * _clipPoints2[i].v.y -
          frontOffset;

      if (separation <= totalRadius) {
        ManifoldPoint cp = manifold.points[pointCount];
        // cp.m_localPoint = MulT(xf2, _clipPoints2[i].v);
        Vec2 out = cp.localPoint;
        final double px = _clipPoints2[i].v.x - xf2.p.x;
        final double py = _clipPoints2[i].v.y - xf2.p.y;
        out.x = (xf2.q.c * px + xf2.q.s * py);
        out.y = (-xf2.q.s * px + xf2.q.c * py);
        cp.id.set(_clipPoints2[i].id);
        if (flip) {
          // Swap features
          cp.id.flip();
        }
        ++pointCount;
      }
    }

    manifold.pointCount = pointCount;
  }

  final Vec2 _Q = new Vec2.zero();
  final Vec2 _e = new Vec2.zero();
  final ContactID _cf = new ContactID();
  final Vec2 _e1 = new Vec2.zero();
  final Vec2 _P = new Vec2.zero();

  // Compute contact points for edge versus circle.
  // This accounts for edge connectivity.
  void collideEdgeAndCircle(Manifold manifold, final EdgeShape edgeA,
      final Transform xfA, final CircleShape circleB, final Transform xfB) {
    manifold.pointCount = 0;

    // Compute circle in frame of edge
    // Vec2 Q = MulT(xfA, Mul(xfB, circleB.m_p));
    Transform.mulToOutUnsafeVec2(xfB, circleB.m_p, _temp);
    Transform.mulTransToOutUnsafeVec2(xfA, _temp, _Q);

    final Vec2 A = edgeA.m_vertex1;
    final Vec2 B = edgeA.m_vertex2;
    _e.set(B).subLocal(A);

    // Barycentric coordinates
    double u = Vec2.dot(_e, _temp.set(B).subLocal(_Q));
    double v = Vec2.dot(_e, _temp.set(_Q).subLocal(A));

    double radius = edgeA.m_radius + circleB.m_radius;

    // ContactFeature cf;
    _cf.indexB = 0;
    _cf.typeB = ContactIDType.VERTEX.index & 0xFF;

    // Region A
    if (v <= 0.0) {
      final Vec2 P = A;
      _d.set(_Q).subLocal(P);
      double dd = Vec2.dot(_d, _d);
      if (dd > radius * radius) {
        return;
      }

      // Is there an edge connected to A?
      if (edgeA.m_hasVertex0) {
        final Vec2 A1 = edgeA.m_vertex0;
        final Vec2 B1 = A;
        _e1.set(B1).subLocal(A1);
        double u1 = Vec2.dot(_e1, _temp.set(B1).subLocal(_Q));

        // Is the circle in Region AB of the previous edge?
        if (u1 > 0.0) {
          return;
        }
      }

      _cf.indexA = 0;
      _cf.typeA = ContactIDType.VERTEX.index & 0xFF;
      manifold.pointCount = 1;
      manifold.type = ManifoldType.CIRCLES;
      manifold.localNormal.setZero();
      manifold.localPoint.set(P);
      // manifold.points[0].id.key = 0;
      manifold.points[0].id.set(_cf);
      manifold.points[0].localPoint.set(circleB.m_p);
      return;
    }

    // Region B
    if (u <= 0.0) {
      Vec2 P = B;
      _d.set(_Q).subLocal(P);
      double dd = Vec2.dot(_d, _d);
      if (dd > radius * radius) {
        return;
      }

      // Is there an edge connected to B?
      if (edgeA.m_hasVertex3) {
        final Vec2 B2 = edgeA.m_vertex3;
        final Vec2 A2 = B;
        final Vec2 e2 = _e1;
        e2.set(B2).subLocal(A2);
        double v2 = Vec2.dot(e2, _temp.set(_Q).subLocal(A2));

        // Is the circle in Region AB of the next edge?
        if (v2 > 0.0) {
          return;
        }
      }

      _cf.indexA = 1;
      _cf.typeA = ContactIDType.VERTEX.index & 0xFF;
      manifold.pointCount = 1;
      manifold.type = ManifoldType.CIRCLES;
      manifold.localNormal.setZero();
      manifold.localPoint.set(P);
      // manifold.points[0].id.key = 0;
      manifold.points[0].id.set(_cf);
      manifold.points[0].localPoint.set(circleB.m_p);
      return;
    }

    // Region AB
    double den = Vec2.dot(_e, _e);
    assert(den > 0.0);

    // Vec2 P = (1.0f / den) * (u * A + v * B);
    _P.set(A).mulLocal(u).addLocal(_temp.set(B).mulLocal(v));
    _P.mulLocal(1.0 / den);
    _d.set(_Q).subLocal(_P);
    double dd = Vec2.dot(_d, _d);
    if (dd > radius * radius) {
      return;
    }

    _n.x = -_e.y;
    _n.y = _e.x;
    if (Vec2.dot(_n, _temp.set(_Q).subLocal(A)) < 0.0) {
      _n.setXY(-_n.x, -_n.y);
    }
    _n.normalize();

    _cf.indexA = 0;
    _cf.typeA = ContactIDType.FACE.index & 0xFF;
    manifold.pointCount = 1;
    manifold.type = ManifoldType.FACE_A;
    manifold.localNormal.set(_n);
    manifold.localPoint.set(A);
    // manifold.points[0].id.key = 0;
    manifold.points[0].id.set(_cf);
    manifold.points[0].localPoint.set(circleB.m_p);
  }

  final EPCollider _collider = new EPCollider();

  void collideEdgeAndPolygon(Manifold manifold, final EdgeShape edgeA,
      final Transform xfA, final PolygonShape polygonB, final Transform xfB) {
    _collider.collide(manifold, edgeA, xfA, polygonB, xfB);
  }

  /**
   * This class collides and edge and a polygon, taking into account edge adjacency.
   */
}

enum VertexType { ISOLATED, CONCAVE, CONVEX }

class EPCollider {
  final TempPolygon m_polygonB = new TempPolygon();

  final Transform m_xf = new Transform.zero();
  final Vec2 m_centroidB = new Vec2.zero();
  Vec2 m_v0 = new Vec2.zero();
  Vec2 m_v1 = new Vec2.zero();
  Vec2 m_v2 = new Vec2.zero();
  Vec2 m_v3 = new Vec2.zero();
  final Vec2 m_normal0 = new Vec2.zero();
  final Vec2 m_normal1 = new Vec2.zero();
  final Vec2 m_normal2 = new Vec2.zero();
  final Vec2 m_normal = new Vec2.zero();

  VertexType m_type1 = VertexType.ISOLATED,
      m_type2 = VertexType.ISOLATED;

  final Vec2 m_lowerLimit = new Vec2.zero();
  final Vec2 m_upperLimit = new Vec2.zero();
  double m_radius = 0.0;
  bool m_front = false;

  EPCollider() {
    for (int i = 0; i < 2; i++) {
      _ie[i] = new ClipVertex();
      _clipPoints1[i] = new ClipVertex();
      _clipPoints2[i] = new ClipVertex();
    }
  }

  final Vec2 _edge1 = new Vec2.zero();
  final Vec2 _temp = new Vec2.zero();
  final Vec2 _edge0 = new Vec2.zero();
  final Vec2 _edge2 = new Vec2.zero();
  final List<ClipVertex> _ie = new List<ClipVertex>(2);
  final List<ClipVertex> _clipPoints1 = new List<ClipVertex>(2);
  final List<ClipVertex> _clipPoints2 = new List<ClipVertex>(2);
  final _ReferenceFace _rf = new _ReferenceFace();
  final EPAxis _edgeAxis = new EPAxis();
  final EPAxis _polygonAxis = new EPAxis();

  void collide(Manifold manifold, final EdgeShape edgeA, final Transform xfA,
      final PolygonShape polygonB, final Transform xfB) {
    Transform.mulTransToOutUnsafe(xfA, xfB, m_xf);
    Transform.mulToOutUnsafeVec2(m_xf, polygonB.m_centroid, m_centroidB);

    m_v0 = edgeA.m_vertex0;
    m_v1 = edgeA.m_vertex1;
    m_v2 = edgeA.m_vertex2;
    m_v3 = edgeA.m_vertex3;

    bool hasVertex0 = edgeA.m_hasVertex0;
    bool hasVertex3 = edgeA.m_hasVertex3;

    _edge1.set(m_v2).subLocal(m_v1);
    _edge1.normalize();
    m_normal1.setXY(_edge1.y, -_edge1.x);
    double offset1 = Vec2.dot(m_normal1, _temp.set(m_centroidB).subLocal(m_v1));
    double offset0 = 0.0,
        offset2 = 0.0;
    bool convex1 = false,
        convex2 = false;

    // Is there a preceding edge?
    if (hasVertex0) {
      _edge0.set(m_v1).subLocal(m_v0);
      _edge0.normalize();
      m_normal0.setXY(_edge0.y, -_edge0.x);
      convex1 = Vec2.cross(_edge0, _edge1) >= 0.0;
      offset0 = Vec2.dot(m_normal0, _temp.set(m_centroidB).subLocal(m_v0));
    }

    // Is there a following edge?
    if (hasVertex3) {
      _edge2.set(m_v3).subLocal(m_v2);
      _edge2.normalize();
      m_normal2.setXY(_edge2.y, -_edge2.x);
      convex2 = Vec2.cross(_edge1, _edge2) > 0.0;
      offset2 = Vec2.dot(m_normal2, _temp.set(m_centroidB).subLocal(m_v2));
    }

    // Determine front or back collision. Determine collision normal limits.
    if (hasVertex0 && hasVertex3) {
      if (convex1 && convex2) {
        m_front = offset0 >= 0.0 || offset1 >= 0.0 || offset2 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal0.x;
          m_lowerLimit.y = m_normal0.y;
          m_upperLimit.x = m_normal2.x;
          m_upperLimit.y = m_normal2.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal1.x;
          m_lowerLimit.y = -m_normal1.y;
          m_upperLimit.x = -m_normal1.x;
          m_upperLimit.y = -m_normal1.y;
        }
      } else if (convex1) {
        m_front = offset0 >= 0.0 || (offset1 >= 0.0 && offset2 >= 0.0);
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal0.x;
          m_lowerLimit.y = m_normal0.y;
          m_upperLimit.x = m_normal1.x;
          m_upperLimit.y = m_normal1.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal2.x;
          m_lowerLimit.y = -m_normal2.y;
          m_upperLimit.x = -m_normal1.x;
          m_upperLimit.y = -m_normal1.y;
        }
      } else if (convex2) {
        m_front = offset2 >= 0.0 || (offset0 >= 0.0 && offset1 >= 0.0);
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal1.x;
          m_lowerLimit.y = m_normal1.y;
          m_upperLimit.x = m_normal2.x;
          m_upperLimit.y = m_normal2.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal1.x;
          m_lowerLimit.y = -m_normal1.y;
          m_upperLimit.x = -m_normal0.x;
          m_upperLimit.y = -m_normal0.y;
        }
      } else {
        m_front = offset0 >= 0.0 && offset1 >= 0.0 && offset2 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal1.x;
          m_lowerLimit.y = m_normal1.y;
          m_upperLimit.x = m_normal1.x;
          m_upperLimit.y = m_normal1.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal2.x;
          m_lowerLimit.y = -m_normal2.y;
          m_upperLimit.x = -m_normal0.x;
          m_upperLimit.y = -m_normal0.y;
        }
      }
    } else if (hasVertex0) {
      if (convex1) {
        m_front = offset0 >= 0.0 || offset1 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal0.x;
          m_lowerLimit.y = m_normal0.y;
          m_upperLimit.x = -m_normal1.x;
          m_upperLimit.y = -m_normal1.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = m_normal1.x;
          m_lowerLimit.y = m_normal1.y;
          m_upperLimit.x = -m_normal1.x;
          m_upperLimit.y = -m_normal1.y;
        }
      } else {
        m_front = offset0 >= 0.0 && offset1 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = m_normal1.x;
          m_lowerLimit.y = m_normal1.y;
          m_upperLimit.x = -m_normal1.x;
          m_upperLimit.y = -m_normal1.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = m_normal1.x;
          m_lowerLimit.y = m_normal1.y;
          m_upperLimit.x = -m_normal0.x;
          m_upperLimit.y = -m_normal0.y;
        }
      }
    } else if (hasVertex3) {
      if (convex2) {
        m_front = offset1 >= 0.0 || offset2 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = -m_normal1.x;
          m_lowerLimit.y = -m_normal1.y;
          m_upperLimit.x = m_normal2.x;
          m_upperLimit.y = m_normal2.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal1.x;
          m_lowerLimit.y = -m_normal1.y;
          m_upperLimit.x = m_normal1.x;
          m_upperLimit.y = m_normal1.y;
        }
      } else {
        m_front = offset1 >= 0.0 && offset2 >= 0.0;
        if (m_front) {
          m_normal.x = m_normal1.x;
          m_normal.y = m_normal1.y;
          m_lowerLimit.x = -m_normal1.x;
          m_lowerLimit.y = -m_normal1.y;
          m_upperLimit.x = m_normal1.x;
          m_upperLimit.y = m_normal1.y;
        } else {
          m_normal.x = -m_normal1.x;
          m_normal.y = -m_normal1.y;
          m_lowerLimit.x = -m_normal2.x;
          m_lowerLimit.y = -m_normal2.y;
          m_upperLimit.x = m_normal1.x;
          m_upperLimit.y = m_normal1.y;
        }
      }
    } else {
      m_front = offset1 >= 0.0;
      if (m_front) {
        m_normal.x = m_normal1.x;
        m_normal.y = m_normal1.y;
        m_lowerLimit.x = -m_normal1.x;
        m_lowerLimit.y = -m_normal1.y;
        m_upperLimit.x = -m_normal1.x;
        m_upperLimit.y = -m_normal1.y;
      } else {
        m_normal.x = -m_normal1.x;
        m_normal.y = -m_normal1.y;
        m_lowerLimit.x = m_normal1.x;
        m_lowerLimit.y = m_normal1.y;
        m_upperLimit.x = m_normal1.x;
        m_upperLimit.y = m_normal1.y;
      }
    }

    // Get polygonB in frameA
    m_polygonB.count = polygonB.m_count;
    for (int i = 0; i < polygonB.m_count; ++i) {
      Transform.mulToOutUnsafeVec2(
          m_xf, polygonB.m_vertices[i], m_polygonB.vertices[i]);
      Rot.mulToOutUnsafe(m_xf.q, polygonB.m_normals[i], m_polygonB.normals[i]);
    }

    m_radius = 2.0 * Settings.polygonRadius;

    manifold.pointCount = 0;

    computeEdgeSeparation(_edgeAxis);

    // If no valid normal can be found than this edge should not collide.
    if (_edgeAxis.type == EPAxisType.UNKNOWN) {
      return;
    }

    if (_edgeAxis.separation > m_radius) {
      return;
    }

    computePolygonSeparation(_polygonAxis);
    if (_polygonAxis.type != EPAxisType.UNKNOWN &&
        _polygonAxis.separation > m_radius) {
      return;
    }

    // Use hysteresis for jitter reduction.
    final double k_relativeTol = 0.98;
    final double k_absoluteTol = 0.001;

    EPAxis primaryAxis;
    if (_polygonAxis.type == EPAxisType.UNKNOWN) {
      primaryAxis = _edgeAxis;
    } else if (_polygonAxis.separation >
        k_relativeTol * _edgeAxis.separation + k_absoluteTol) {
      primaryAxis = _polygonAxis;
    } else {
      primaryAxis = _edgeAxis;
    }

    final ClipVertex ie0 = _ie[0];
    final ClipVertex ie1 = _ie[1];

    if (primaryAxis.type == EPAxisType.EDGE_A) {
      manifold.type = ManifoldType.FACE_A;

      // Search for the polygon normal that is most anti-parallel to the edge normal.
      int bestIndex = 0;
      double bestValue = Vec2.dot(m_normal, m_polygonB.normals[0]);
      for (int i = 1; i < m_polygonB.count; ++i) {
        double value = Vec2.dot(m_normal, m_polygonB.normals[i]);
        if (value < bestValue) {
          bestValue = value;
          bestIndex = i;
        }
      }

      int i1 = bestIndex;
      int i2 = i1 + 1 < m_polygonB.count ? i1 + 1 : 0;

      ie0.v.set(m_polygonB.vertices[i1]);
      ie0.id.indexA = 0;
      ie0.id.indexB = i1 & 0xFF;
      ie0.id.typeA = ContactIDType.FACE.index & 0xFF;
      ie0.id.typeB = ContactIDType.VERTEX.index & 0xFF;

      ie1.v.set(m_polygonB.vertices[i2]);
      ie1.id.indexA = 0;
      ie1.id.indexB = i2 & 0xFF;
      ie1.id.typeA = ContactIDType.FACE.index & 0xFF;
      ie1.id.typeB = ContactIDType.VERTEX.index & 0xFF;

      if (m_front) {
        _rf.i1 = 0;
        _rf.i2 = 1;
        _rf.v1.set(m_v1);
        _rf.v2.set(m_v2);
        _rf.normal.set(m_normal1);
      } else {
        _rf.i1 = 1;
        _rf.i2 = 0;
        _rf.v1.set(m_v2);
        _rf.v2.set(m_v1);
        _rf.normal.set(m_normal1).negateLocal();
      }
    } else {
      manifold.type = ManifoldType.FACE_B;

      ie0.v.set(m_v1);
      ie0.id.indexA = 0;
      ie0.id.indexB = primaryAxis.index & 0xFF;
      ie0.id.typeA = ContactIDType.VERTEX.index & 0xFF;
      ie0.id.typeB = ContactIDType.FACE.index & 0xFF;

      ie1.v.set(m_v2);
      ie1.id.indexA = 0;
      ie1.id.indexB = primaryAxis.index & 0xFF;
      ie1.id.typeA = ContactIDType.VERTEX.index & 0xFF;
      ie1.id.typeB = ContactIDType.FACE.index & 0xFF;

      _rf.i1 = primaryAxis.index;
      _rf.i2 = _rf.i1 + 1 < m_polygonB.count ? _rf.i1 + 1 : 0;
      _rf.v1.set(m_polygonB.vertices[_rf.i1]);
      _rf.v2.set(m_polygonB.vertices[_rf.i2]);
      _rf.normal.set(m_polygonB.normals[_rf.i1]);
    }

    _rf.sideNormal1.setXY(_rf.normal.y, -_rf.normal.x);
    _rf.sideNormal2.set(_rf.sideNormal1).negateLocal();
    _rf.sideOffset1 = Vec2.dot(_rf.sideNormal1, _rf.v1);
    _rf.sideOffset2 = Vec2.dot(_rf.sideNormal2, _rf.v2);

    // Clip incident edge against extruded edge1 side edges.
    int np;

    // Clip to box side 1
    np = Collision.clipSegmentToLine(
        _clipPoints1, _ie, _rf.sideNormal1, _rf.sideOffset1, _rf.i1);

    if (np < Settings.maxManifoldPoints) {
      return;
    }

    // Clip to negative box side 1
    np = Collision.clipSegmentToLine(
        _clipPoints2, _clipPoints1, _rf.sideNormal2, _rf.sideOffset2, _rf.i2);

    if (np < Settings.maxManifoldPoints) {
      return;
    }

    // Now _clipPoints2 contains the clipped points.
    if (primaryAxis.type == EPAxisType.EDGE_A) {
      manifold.localNormal.set(_rf.normal);
      manifold.localPoint.set(_rf.v1);
    } else {
      manifold.localNormal.set(polygonB.m_normals[_rf.i1]);
      manifold.localPoint.set(polygonB.m_vertices[_rf.i1]);
    }

    int pointCount = 0;
    for (int i = 0; i < Settings.maxManifoldPoints; ++i) {
      double separation;

      separation =
          Vec2.dot(_rf.normal, _temp.set(_clipPoints2[i].v).subLocal(_rf.v1));

      if (separation <= m_radius) {
        ManifoldPoint cp = manifold.points[pointCount];

        if (primaryAxis.type == EPAxisType.EDGE_A) {
          // cp.localPoint = MulT(m_xf, _clipPoints2[i].v);
          Transform.mulTransToOutUnsafeVec2(
              m_xf, _clipPoints2[i].v, cp.localPoint);
          cp.id.set(_clipPoints2[i].id);
        } else {
          cp.localPoint.set(_clipPoints2[i].v);
          cp.id.typeA = _clipPoints2[i].id.typeB;
          cp.id.typeB = _clipPoints2[i].id.typeA;
          cp.id.indexA = _clipPoints2[i].id.indexB;
          cp.id.indexB = _clipPoints2[i].id.indexA;
        }

        ++pointCount;
      }
    }

    manifold.pointCount = pointCount;
  }

  void computeEdgeSeparation(EPAxis axis) {
    axis.type = EPAxisType.EDGE_A;
    axis.index = m_front ? 0 : 1;
    axis.separation = double.MAX_FINITE;
    double nx = m_normal.x;
    double ny = m_normal.y;

    for (int i = 0; i < m_polygonB.count; ++i) {
      Vec2 v = m_polygonB.vertices[i];
      double tempx = v.x - m_v1.x;
      double tempy = v.y - m_v1.y;
      double s = nx * tempx + ny * tempy;
      if (s < axis.separation) {
        axis.separation = s;
      }
    }
  }

  final Vec2 _perp = new Vec2.zero();
  final Vec2 _n = new Vec2.zero();

  void computePolygonSeparation(EPAxis axis) {
    axis.type = EPAxisType.UNKNOWN;
    axis.index = -1;
    axis.separation = -double.MAX_FINITE;

    _perp.x = -m_normal.y;
    _perp.y = m_normal.x;

    for (int i = 0; i < m_polygonB.count; ++i) {
      Vec2 normalB = m_polygonB.normals[i];
      Vec2 vB = m_polygonB.vertices[i];
      _n.x = -normalB.x;
      _n.y = -normalB.y;

      // double s1 = Vec2.dot(n, temp.set(vB).subLocal(m_v1));
      // double s2 = Vec2.dot(n, temp.set(vB).subLocal(m_v2));
      double tempx = vB.x - m_v1.x;
      double tempy = vB.y - m_v1.y;
      double s1 = _n.x * tempx + _n.y * tempy;
      tempx = vB.x - m_v2.x;
      tempy = vB.y - m_v2.y;
      double s2 = _n.x * tempx + _n.y * tempy;
      double s = Math.min(s1, s2);

      if (s > m_radius) {
        // No collision
        axis.type = EPAxisType.EDGE_B;
        axis.index = i;
        axis.separation = s;
        return;
      }

      // Adjacency
      if (_n.x * _perp.x + _n.y * _perp.y >= 0.0) {
        if (Vec2.dot(_temp.set(_n).subLocal(m_upperLimit), m_normal) <
            -Settings.angularSlop) {
          continue;
        }
      } else {
        if (Vec2.dot(_temp.set(_n).subLocal(m_lowerLimit), m_normal) <
            -Settings.angularSlop) {
          continue;
        }
      }

      if (s > axis.separation) {
        axis.type = EPAxisType.EDGE_B;
        axis.index = i;
        axis.separation = s;
      }
    }
  }
}
