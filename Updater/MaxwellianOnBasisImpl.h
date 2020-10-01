#include <cmath>
#include <stdio.h>
extern "C" {
  void MaxwellianInnerLoop(double * n, double * u, double * vth2,
			   double * fItr,
			   double * weights, double * dz, double * zc,
			   double * ordinates,
			   double * basisAtOrdinates,
			   double * phaseToConfOrdMap,
			   int numPhaseBasis,
			   int numConfOrds, int numPhaseOrds,
			   int numConfDims, int numPhaseDims);

  void GkMaxwellianInnerLoop(double * n, double * u, double * vth2, double * bmag, double m_,
			     double * fItr,
			     double * weights, double * dz, double * zc,
			     double * ordinates,
			     double * basisAtOrdinates,
			     double * phaseToConfOrdMap,
			     int numPhaseBasis,
			     int numConfOrds, int numPhaseOrds,
			     int numConfDims, int numPhaseDims);
 
}
