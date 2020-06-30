/**
 * @file ex_particle_OPENMP_seq.c
 * @author Michael Trotter & Matt Goodrum
 * @brief Particle filter implementation in C/OpenMP 
 */

 ////////////////////////////////////////////////////////////////////////////////////////////////////
 // file:	altis\src\cuda\level2\particlefilter\ex_particle_CUDA_naive_seq.cu
 //
 // summary:	Exception particle cuda float sequence class
 // 
 // origin: Rodinia (http://rodinia.cs.virginia.edu/doku.php)
 ////////////////////////////////////////////////////////////////////////////////////////////////////


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <float.h>
#include <sys/time.h>
#include "OptionParser.h"
#include "ResultDatabase.h"
#include "cudacommon.h"

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @def	PI
///
/// @brief	A macro that defines pi
///
/// @author	Ed
/// @date	5/20/2020
////////////////////////////////////////////////////////////////////////////////////////////////////

#define PI 3.1415926535897932

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @def	BLOCK_X
///
/// @brief	A macro that defines block X coordinate
///
/// @author	Ed
/// @date	5/20/2020
////////////////////////////////////////////////////////////////////////////////////////////////////

#define BLOCK_X 16

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @def	BLOCK_Y
///
/// @brief	A macro that defines block Y coordinate
///
/// @author	Ed
/// @date	5/20/2020
////////////////////////////////////////////////////////////////////////////////////////////////////

#define BLOCK_Y 16

/// @brief	True to verbose
bool verbose = false;
/// @brief	True to quiet
bool quiet = false;

/// @brief	@var M value for Linear Congruential Generator (LCG); use GCC's value
long M = INT_MAX;
/// @brief	@var A value for LCG
int A = 1103515245;
/// @brief	@var C value for LCG
int C = 12345;

/// @brief	The threads per block
const int threads_per_block = 128;

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	__device__ int findIndexSeq(double * CDF, int lengthCDF, double value)
///
/// @brief	Searches for the first index sequence
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	CDF		 	If non-null, the cdf. 
/// @param 		   	lengthCDF	The length cdf. 
/// @param 		   	value	 	The value. 
///
/// @returns	The found index sequence.
////////////////////////////////////////////////////////////////////////////////////////////////////

__device__ int findIndexSeq(double * CDF, int lengthCDF, double value)
{
	int index = -1;
	int x;
	for(x = 0; x < lengthCDF; x++)
	{
		if(CDF[x] >= value)
		{
			index = x;
			break;
		}
	}
	if(index == -1)
		return lengthCDF-1;
	return index;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	__device__ int findIndexBin(double * CDF, int beginIndex, int endIndex, double value)
///
/// @brief	Searches for the first index bin
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	CDF		  	If non-null, the cdf. 
/// @param 		   	beginIndex	Zero-based index of the begin. 
/// @param 		   	endIndex  	The end index. 
/// @param 		   	value	  	The value. 
///
/// @returns	The found index bin.
////////////////////////////////////////////////////////////////////////////////////////////////////

__device__ int findIndexBin(double * CDF, int beginIndex, int endIndex, double value)
{
	if(endIndex < beginIndex)
		return -1;
	int middleIndex;
	while(endIndex > beginIndex)
	{
		middleIndex = beginIndex + ((endIndex-beginIndex)/2);
		if(CDF[middleIndex] >= value)
		{
			if(middleIndex == 0)
				return middleIndex;
			else if(CDF[middleIndex-1] < value)
				return middleIndex;
			else if(CDF[middleIndex-1] == value)
			{
				while(CDF[middleIndex] == value && middleIndex >= 0)
					middleIndex--;
				middleIndex++;
				return middleIndex;
			}
		}
		if(CDF[middleIndex] > value)
			endIndex = middleIndex-1;
		else
			beginIndex = middleIndex+1;
	}
	return -1;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	* CUDA Kernel Function to replace FindIndex * param1: arrayX * param2: arrayY * param3: CDF * param4: u * param5: xj * param6: yj * param7: Nparticles *****************************/ __global__ void kernel(double * arrayX, double * arrayY, double * CDF, double * u, double * xj, double * yj, int Nparticles)
///
/// @brief	Kernels
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	arrayX	  	If non-null, the array x coordinate. 
/// @param [in,out]	arrayY	  	If non-null, the array y coordinate. 
/// @param [in,out]	CDF		  	If non-null, the cdf. 
/// @param [in,out]	u		  	If non-null, a double to process. 
/// @param [in,out]	xj		  	If non-null, the xj. 
/// @param [in,out]	yj		  	If non-null, the yj. 
/// @param 		   	Nparticles	The nparticles. 
////////////////////////////////////////////////////////////////////////////////////////////////////

__global__ void kernel(double * arrayX, double * arrayY, double * CDF, double * u, double * xj, double * yj, int Nparticles){
	int block_id = blockIdx.x;// + gridDim.x * blockIdx.y;
	int i = blockDim.x * block_id + threadIdx.x;
	
	if(i < Nparticles){
	
		int index = -1;
		int x;
		
		for(x = 0; x < Nparticles; x++){
			if(CDF[x] >= u[i]){
				index = x;
				break;
			}
		}
		if(index == -1){
			index = Nparticles-1;
		}
		
		xj[i] = arrayX[index];
		yj[i] = arrayY[index];
		
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	double roundDouble(double value)
///
/// @brief	Takes in a double and returns an integer that approximates to that double
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param 	value	The value. 
///
/// @returns	if the mantissa &lt; .5 =&gt; return value &lt; input value; else return value
/// 			&gt; input value.
////////////////////////////////////////////////////////////////////////////////////////////////////

double roundDouble(double value){
	int newValue = (int)(value);
	if(value - newValue < .5)
	return newValue;
	else
	return newValue++;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void setIf(int testValue, int newValue, int * array3D, int * dimX, int * dimY, int * dimZ)
///
/// @brief	Set values of the 3D array to a newValue if that value is equal to the testValue
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param 		   	testValue	The value to be replaced. 
/// @param 		   	newValue 	The value to replace testValue with. 
/// @param [in,out]	array3D  	The image vector. 
/// @param [in,out]	dimX	 	The x dimension of the frame. 
/// @param [in,out]	dimY	 	The y dimension of the frame. 
/// @param [in,out]	dimZ	 	The number of frames. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void setIf(int testValue, int newValue, int * array3D, int * dimX, int * dimY, int * dimZ){
	int x, y, z;
	for(x = 0; x < *dimX; x++){
		for(y = 0; y < *dimY; y++){
			for(z = 0; z < *dimZ; z++){
				if(array3D[x * *dimY * *dimZ+y * *dimZ + z] == testValue)
				array3D[x * *dimY * *dimZ + y * *dimZ + z] = newValue;
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	double randu(int * seed, int index)
///
/// @brief	Generates a uniformly distributed random number using the provided seed and GCC's
/// 		settings for the Linear Congruential Generator (LCG)
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	seed 	The seed array. 
/// @param 		   	index	The specific index of the seed to be advanced. 
///
/// @returns	a uniformly distributed number [0, 1)
///
/// @sa	http://en.wikipedia.org/wiki/Linear_congruential_generator
/// 	@note This function is thread-safe
////////////////////////////////////////////////////////////////////////////////////////////////////

double randu(int * seed, int index)
{
	int num = A*seed[index] + C;
	seed[index] = num % M;
	return fabs(seed[index]/((double) M));
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	double randn(int * seed, int index)
///
/// @brief	Generates a normally distributed random number using the Box-Muller transformation
/// 		@note This function is thread-safe
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	seed 	The seed array. 
/// @param 		   	index	The specific index of the seed to be advanced. 
///
/// @returns	a double representing random number generated using the Box-Muller algorithm.
///
/// @sa	http://en.wikipedia.org/wiki/Normal_distribution, section computing value for normal
/// 	random distribution
////////////////////////////////////////////////////////////////////////////////////////////////////

double randn(int * seed, int index){
	/*Box-Muller algorithm*/
	double u = randu(seed, index);
	double v = randu(seed, index);
	double cosine = cos(2*PI*v);
	double rt = -2*log(u);
	return sqrt(rt)*cosine;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void addNoise(int * array3D, int * dimX, int * dimY, int * dimZ, int * seed)
///
/// @brief	Sets values of 3D matrix using randomly generated numbers from a normal distribution
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	array3D	The video to be modified. 
/// @param [in,out]	dimX   	The x dimension of the frame. 
/// @param [in,out]	dimY   	The y dimension of the frame. 
/// @param [in,out]	dimZ   	The number of frames. 
/// @param [in,out]	seed   	The seed array. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void addNoise(int * array3D, int * dimX, int * dimY, int * dimZ, int * seed){
	int x, y, z;
	for(x = 0; x < *dimX; x++){
		for(y = 0; y < *dimY; y++){
			for(z = 0; z < *dimZ; z++){
				array3D[x * *dimY * *dimZ + y * *dimZ + z] = array3D[x * *dimY * *dimZ + y * *dimZ + z] + (int)(5*randn(seed, 0));
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void strelDisk(int * disk, int radius)
///
/// @brief	Fills a radius x radius matrix representing the disk
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	disk  	The pointer to the disk to be made. 
/// @param 		   	radius	The radius of the disk to be made. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void strelDisk(int * disk, int radius)
{
	int diameter = radius*2 - 1;
	int x, y;
	for(x = 0; x < diameter; x++){
		for(y = 0; y < diameter; y++){
			double distance = sqrt(pow((double)(x-radius+1),2) + pow((double)(y-radius+1),2));
			if(distance < radius) {
			    disk[x*diameter + y] = 1;
            } else {
			    disk[x*diameter + y] = 0;
            }
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void dilate_matrix(int * matrix, int posX, int posY, int posZ, int dimX, int dimY, int dimZ, int error)
///
/// @brief	Dilates the provided video
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	matrix	The video to be dilated. 
/// @param 		   	posX  	The x location of the pixel to be dilated. 
/// @param 		   	posY  	The y location of the pixel to be dilated. 
/// @param 		   	posZ  	The z location of the pixel to be dilated. 
/// @param 		   	dimX  	The x dimension of the frame. 
/// @param 		   	dimY  	The y dimension of the frame. 
/// @param 		   	dimZ  	The number of frames. 
/// @param 		   	error 	The error radius. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void dilate_matrix(int * matrix, int posX, int posY, int posZ, int dimX, int dimY, int dimZ, int error)
{
	int startX = posX - error;
	while(startX < 0)
	startX++;
	int startY = posY - error;
	while(startY < 0)
	startY++;
	int endX = posX + error;
	while(endX > dimX)
	endX--;
	int endY = posY + error;
	while(endY > dimY)
	endY--;
	int x,y;
	for(x = startX; x < endX; x++){
		for(y = startY; y < endY; y++){
			double distance = sqrt( pow((double)(x-posX),2) + pow((double)(y-posY),2) );
			if(distance < error)
			matrix[x*dimY*dimZ + y*dimZ + posZ] = 1;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void imdilate_disk(int * matrix, int dimX, int dimY, int dimZ, int error, int * newMatrix)
///
/// @brief	Dilates the target matrix using the radius as a guide
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	matrix   	The reference matrix. 
/// @param 		   	dimX	 	The x dimension of the video. 
/// @param 		   	dimY	 	The y dimension of the video. 
/// @param 		   	dimZ	 	The z dimension of the video. 
/// @param 		   	error	 	The error radius to be dilated. 
/// @param [in,out]	newMatrix	The target matrix. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void imdilate_disk(int * matrix, int dimX, int dimY, int dimZ, int error, int * newMatrix)
{
	int x, y, z;
	for(z = 0; z < dimZ; z++){
		for(x = 0; x < dimX; x++){
			for(y = 0; y < dimY; y++){
				if(matrix[x*dimY*dimZ + y*dimZ + z] == 1){
					dilate_matrix(newMatrix, x, y, z, dimX, dimY, dimZ, error);
				}
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void getneighbors(int * se, int numOnes, double * neighbors, int radius)
///
/// @brief	Fills a 2D array describing the offsets of the disk object
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	se		 	The disk object. 
/// @param 		   	numOnes  	The number of ones in the disk. 
/// @param [in,out]	neighbors	The array that will contain the offsets. 
/// @param 		   	radius   	The radius used for dilation. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void getneighbors(int * se, int numOnes, double * neighbors, int radius){
	int x, y;
	int neighY = 0;
	int center = radius - 1;
	int diameter = radius*2 -1;
	for(x = 0; x < diameter; x++){
		for(y = 0; y < diameter; y++){
			if(se[x*diameter + y]){
				neighbors[neighY*2] = (int)(y - center);
				neighbors[neighY*2 + 1] = (int)(x - center);
				neighY++;
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void videoSequence(int * I, int IszX, int IszY, int Nfr, int * seed)
///
/// @brief	The synthetic video sequence we will work with here is composed of a single moving
/// 		object, circular in shape (fixed radius)
/// 		The motion here is a linear motion the foreground intensity and the backgrounf
/// 		intensity is known the image is corrupted with zero mean Gaussian noise
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	I   	The video itself. 
/// @param 		   	IszX	The x dimension of the video. 
/// @param 		   	IszY	The y dimension of the video. 
/// @param 		   	Nfr 	The number of frames of the video. 
/// @param [in,out]	seed	The seed array used for number generation. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void videoSequence(int * I, int IszX, int IszY, int Nfr, int * seed){
	int k;
	int max_size = IszX*IszY*Nfr;
	/*get object centers*/
	int x0 = (int)roundDouble(IszY/2.0);
	int y0 = (int)roundDouble(IszX/2.0);
	I[x0 *IszY *Nfr + y0 * Nfr  + 0] = 1;
	
	/*move point*/
	int xk, yk, pos;
	for(k = 1; k < Nfr; k++){
		xk = abs(x0 + (k-1));
		yk = abs(y0 - 2*(k-1));
		pos = yk * IszY * Nfr + xk *Nfr + k;
		if(pos >= max_size)
		pos = 0;
		I[pos] = 1;
	}
	
	/*dilate matrix*/
#ifdef UNIFIED_MEMORY
    int *newMatrix = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&newMatrix, sizeof(int) * IszX * IszY * Nfr));
#else
	int * newMatrix = (int *)malloc(sizeof(int)*IszX*IszY*Nfr);
#endif
	imdilate_disk(I, IszX, IszY, Nfr, 5, newMatrix);
	int x, y;
	for(x = 0; x < IszX; x++){
		for(y = 0; y < IszY; y++){
			for(k = 0; k < Nfr; k++){
				I[x*IszY*Nfr + y*Nfr + k] = newMatrix[x*IszY*Nfr + y*Nfr + k];
			}
		}
	}
#ifdef UNIFIED_MEMORY
    CUDA_SAFE_CALL(cudaFree(newMatrix));
#else
	free(newMatrix);
#endif
	
	/*define background, add noise*/
	setIf(0, 100, I, &IszX, &IszY, &Nfr);
	setIf(1, 228, I, &IszX, &IszY, &Nfr);
	/*add noise*/
	addNoise(I, &IszX, &IszY, &Nfr, seed);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	double calcLikelihoodSum(int * I, int * ind, int numOnes)
///
/// @brief	Determines the likelihood sum based on the formula: SUM( (IK[IND] - 100)^2 - (IK[IND]
/// 		- 228)^2)/ 100
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	I	   	The 3D matrix. 
/// @param [in,out]	ind	   	The current ind array. 
/// @param 		   	numOnes	The length of ind array. 
///
/// @returns	A double representing the sum.
////////////////////////////////////////////////////////////////////////////////////////////////////

double calcLikelihoodSum(int * I, int * ind, int numOnes){
	double likelihoodSum = 0.0;
	int y;
	for(y = 0; y < numOnes; y++)
	likelihoodSum += (pow((double)(I[ind[y]] - 100),2) - pow((double)(I[ind[y]]-228),2))/50.0;
	return likelihoodSum;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	int findIndex(double * CDF, int lengthCDF, double value)
///
/// @brief	Finds the first element in the CDF that is greater than or equal to the provided
/// 		value and returns that index
/// 		@note This function uses sequential search
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	CDF		 	The CDF. 
/// @param 		   	lengthCDF	The length of CDF. 
/// @param 		   	value	 	The value to be found. 
///
/// @returns	The index of value in the CDF; if value is never found, returns the last index.
////////////////////////////////////////////////////////////////////////////////////////////////////

int findIndex(double * CDF, int lengthCDF, double value){
	int index = -1;
	int x;
	for(x = 0; x < lengthCDF; x++){
		if(CDF[x] >= value){
			index = x;
			break;
		}
	}
	if(index == -1){
		return lengthCDF-1;
	}
	return index;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void particleFilter(int * I, int IszX, int IszY, int Nfr, int * seed, int Nparticles, ResultDatabase &resultDB)
///
/// @brief	The implementation of the particle filter using OpenMP for many frames
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	I		  	The video to be run. 
/// @param 		   	IszX	  	The x dimension of the video. 
/// @param 		   	IszY	  	The y dimension of the video. 
/// @param 		   	Nfr		  	The number of frames. 
/// @param [in,out]	seed	  	The seed array used for random number generation. 
/// @param 		   	Nparticles	The number of particles to be used. 
/// @param [in,out]	resultDB  	The result database. 
///
/// @sa	http://openmp.org/wp/
/// 	@note This function is designed to work with a video of several frames. In addition, it
/// 	references a provided MATLAB function which takes the video, the objxy matrix and the x
/// 	and y arrays as arguments and returns the likelihoods
////////////////////////////////////////////////////////////////////////////////////////////////////

void particleFilter(int * I, int IszX, int IszY, int Nfr, int * seed, int Nparticles, ResultDatabase &resultDB) {

    float kernelTime = 0.0f;
    float transferTime = 0.0f;
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    float elapsedTime;

	int max_size = IszX*IszY*Nfr;
	//original particle centroid
	double xe = roundDouble(IszY/2.0);
	double ye = roundDouble(IszX/2.0);
	
	//expected object locations, compared to center
	int radius = 5;
	int diameter = radius*2 - 1;
#ifdef UNIFIED_MEMORY
    int *disk = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&disk, diameter * diameter * sizeof(int)));
#else
	int * disk = (int *)malloc(diameter*diameter*sizeof(int));
#endif
	strelDisk(disk, radius);
	int countOnes = 0;
	int x, y;
	for(x = 0; x < diameter; x++){
		for(y = 0; y < diameter; y++){
			if(disk[x*diameter + y] == 1)
				countOnes++;
		}
	}
#ifdef UNIFIED_MEMORY
    double *objxy = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&objxy, countOnes*2*sizeof(double)));
#else
	double * objxy = (double *)malloc(countOnes*2*sizeof(double));
#endif
	getneighbors(disk, countOnes, objxy, radius);
	
	//initial weights are all equal (1/Nparticles)
#ifdef UNIFIED_MEMORY
    double *weights = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&weights, sizeof(double) * Nparticles));
#else
	double * weights = (double *)malloc(sizeof(double)*Nparticles);
#endif
	for(x = 0; x < Nparticles; x++){
		weights[x] = 1/((double)(Nparticles));
	}
	//initial likelihood to 0.0
#ifdef UNIFIED_MEMORY
    double *likelihood = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&likelihood, sizeof(double) * Nparticles));
    double *arrayX = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&arrayX, sizeof(double) * Nparticles));
    double *arrayY = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&arrayY, sizeof(double) * Nparticles));
    double *xj = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&xj, sizeof(double) * Nparticles));
    double *yj = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&yj, sizeof(double) * Nparticles));
    double *CDF = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&CDF, sizeof(double) * Nparticles));
#else
	double * likelihood = (double *)malloc(sizeof(double)*Nparticles);
	double * arrayX = (double *)malloc(sizeof(double)*Nparticles);
	double * arrayY = (double *)malloc(sizeof(double)*Nparticles);
	double * xj = (double *)malloc(sizeof(double)*Nparticles);
	double * yj = (double *)malloc(sizeof(double)*Nparticles);
	double * CDF = (double *)malloc(sizeof(double)*Nparticles);
#endif
	
	//GPU copies of arrays
	double * arrayX_GPU;
	double * arrayY_GPU;
	double * xj_GPU;
	double * yj_GPU;
	double * CDF_GPU;
	
#ifdef UNIFIED_MEMORY
    int *ind = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&ind, sizeof(int) * countOnes));
    double *u = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&u, sizeof(double) * Nparticles));
#else
	int * ind = (int*)malloc(sizeof(int)*countOnes);
	double * u = (double *)malloc(sizeof(double)*Nparticles);
#endif
	double * u_GPU;
	
	//CUDA memory allocation
#ifdef UNIFIED_MEMORY
    arrayX_GPU = arrayX;
    arrayY_GPU = arrayY;
    xj_GPU = xj;
    yj_GPU = yj;
    CDF_GPU = CDF;
    u_GPU = u;
#else
	CUDA_SAFE_CALL(cudaMalloc((void **) &arrayX_GPU, sizeof(double)*Nparticles));
	CUDA_SAFE_CALL(cudaMalloc((void **) &arrayY_GPU, sizeof(double)*Nparticles));
	CUDA_SAFE_CALL(cudaMalloc((void **) &xj_GPU, sizeof(double)*Nparticles));
	CUDA_SAFE_CALL(cudaMalloc((void **) &yj_GPU, sizeof(double)*Nparticles));
	CUDA_SAFE_CALL(cudaMalloc((void **) &CDF_GPU, sizeof(double)*Nparticles));
	CUDA_SAFE_CALL(cudaMalloc((void **) &u_GPU, sizeof(double)*Nparticles));
#endif
	
	for(x = 0; x < Nparticles; x++){
		arrayX[x] = xe;
		arrayY[x] = ye;
	}
	int k;
	//double * Ik = (double *)malloc(sizeof(double)*IszX*IszY);
	int indX, indY;
	for(k = 1; k < Nfr; k++){
		//apply motion model
		//draws sample from motion model (random walk). The only prior information
		//is that the object moves 2x as fast as in the y direction
		
		for(x = 0; x < Nparticles; x++){
			arrayX[x] = arrayX[x] + 1.0 + 5.0*randn(seed, x);
			arrayY[x] = arrayY[x] - 2.0 + 2.0*randn(seed, x);
		}
		//particle filter likelihood
		for(x = 0; x < Nparticles; x++){
		
			//compute the likelihood: remember our assumption is that you know
			// foreground and the background image intensity distribution.
			// Notice that we consider here a likelihood ratio, instead of
			// p(z|x). It is possible in this case. why? a hometask for you.		
			//calc ind
			for(y = 0; y < countOnes; y++){
				indX = roundDouble(arrayX[x]) + objxy[y*2 + 1];
				indY = roundDouble(arrayY[x]) + objxy[y*2];
				ind[y] = fabs(indX*IszY*Nfr + indY*Nfr + k);
				if(ind[y] >= max_size)
					ind[y] = 0;
			}
			likelihood[x] = calcLikelihoodSum(I, ind, countOnes);
			likelihood[x] = likelihood[x]/countOnes;
		}
		// update & normalize weights
		// using equation (63) of Arulampalam Tutorial		
		for(x = 0; x < Nparticles; x++){
			weights[x] = weights[x] * exp(likelihood[x]);
		}
		double sumWeights = 0;	
		for(x = 0; x < Nparticles; x++){
			sumWeights += weights[x];
		}
		for(x = 0; x < Nparticles; x++){
				weights[x] = weights[x]/sumWeights;
		}
		xe = 0;
		ye = 0;
		// estimate the object location by expected values
		for(x = 0; x < Nparticles; x++){
			xe += arrayX[x] * weights[x];
			ye += arrayY[x] * weights[x];
		}
        if(verbose && !quiet) {
            printf("XE: %lf\n", xe);
            printf("YE: %lf\n", ye);
            double distance = sqrt( pow((double)(xe-(int)roundDouble(IszY/2.0)),2) + pow((double)(ye-(int)roundDouble(IszX/2.0)),2) );
            printf("%lf\n", distance);
        }
		//display(hold off for now)
		
		//pause(hold off for now)
		
		//resampling
		
		
		CDF[0] = weights[0];
		for(x = 1; x < Nparticles; x++){
			CDF[x] = weights[x] + CDF[x-1];
		}
		double u1 = (1/((double)(Nparticles)))*randu(seed, 0);
		for(x = 0; x < Nparticles; x++){
			u[x] = u1 + x/((double)(Nparticles));
		}
		//CUDA memory copying from CPU memory to GPU memory
        cudaEventRecord(start, 0);

#ifdef UNIFIED_MEMORY
        // Use demand paging, or hyperq async cpy
#else
		cudaMemcpy(arrayX_GPU, arrayX, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
		cudaMemcpy(arrayY_GPU, arrayY, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
		cudaMemcpy(xj_GPU, xj, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
		cudaMemcpy(yj_GPU, yj, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
		cudaMemcpy(CDF_GPU, CDF, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
		cudaMemcpy(u_GPU, u, sizeof(double)*Nparticles, cudaMemcpyHostToDevice);
#endif

        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsedTime, start, stop);
        transferTime += elapsedTime * 1.e-3;
		//Set number of threads
		int num_blocks = ceil((double) Nparticles/(double) threads_per_block);
		
		//KERNEL FUNCTION CALL
        cudaEventRecord(start, 0);
		kernel <<< num_blocks, threads_per_block >>> (arrayX_GPU, arrayY_GPU, CDF_GPU, u_GPU, xj_GPU, yj_GPU, Nparticles);
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsedTime, start, stop);
        kernelTime += elapsedTime * 1.e-3;
        CHECK_CUDA_ERROR();
        
        cudaDeviceSynchronize();
		//CUDA memory copying back from GPU to CPU memory
        cudaEventRecord(start, 0);
#ifdef UNIFIED_MEMORY
        // no need for copy right now, could use demand paging or async stream
#else
		cudaMemcpy(yj, yj_GPU, sizeof(double)*Nparticles, cudaMemcpyDeviceToHost);
		cudaMemcpy(xj, xj_GPU, sizeof(double)*Nparticles, cudaMemcpyDeviceToHost);
#endif
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsedTime, start, stop);
        transferTime += elapsedTime * 1.e-3;
		
		for(x = 0; x < Nparticles; x++){
			//reassign arrayX and arrayY
			arrayX[x] = xj[x];
			arrayY[x] = yj[x];
			weights[x] = 1/((double)(Nparticles));
		}
	}
    
    char atts[1024];
    sprintf(atts, "dimx:%d, dimy:%d, numframes:%d, numparticles:%d", IszX, IszY, Nfr, Nparticles);
    resultDB.AddResult("particlefilter_naive_kernel_time", atts, "sec", kernelTime);
    resultDB.AddResult("particlefilter_naive_transfer_time", atts, "sec", transferTime);
    resultDB.AddResult("particlefilter_naive_total_time", atts, "sec", kernelTime+transferTime);
    resultDB.AddResult("particlefilter_naive_parity", atts, "N", transferTime / kernelTime);
    resultDB.AddOverall("Time", "sec", kernelTime+transferTime);
	
	//CUDA freeing of memory
#ifndef UNIFIED_MEMORY
	cudaFree(u_GPU);
	cudaFree(CDF_GPU);
	cudaFree(yj_GPU);
	cudaFree(xj_GPU);
	cudaFree(arrayY_GPU);
	cudaFree(arrayX_GPU);
#endif
	
	//free memory
#ifdef UNIFIED_MEMORY
    CUDA_SAFE_CALL(cudaFree(disk));
    CUDA_SAFE_CALL(cudaFree(objxy));
    CUDA_SAFE_CALL(cudaFree(weights));
    CUDA_SAFE_CALL(cudaFree(likelihood));
    CUDA_SAFE_CALL(cudaFree(arrayX));
    CUDA_SAFE_CALL(cudaFree(arrayY));
    CUDA_SAFE_CALL(cudaFree(xj));
    CUDA_SAFE_CALL(cudaFree(yj));
    CUDA_SAFE_CALL(cudaFree(CDF));
    CUDA_SAFE_CALL(cudaFree(u));
    CUDA_SAFE_CALL(cudaFree(ind));
#else
	free(disk);
	free(objxy);
	free(weights);
	free(likelihood);
	free(arrayX);
	free(arrayY);
	free(xj);
	free(yj);
	free(CDF);
	free(u);
	free(ind);
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void addBenchmarkSpecOptions(OptionParser &op)
///
/// @brief	Adds a benchmark specifier options
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	op	The operation. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void addBenchmarkSpecOptions(OptionParser &op) {
  op.addOption("dimx", OPT_INT, "0", "grid x dimension", 'x');
  op.addOption("dimy", OPT_INT, "0", "grid y dimension", 'y');
  op.addOption("framecount", OPT_INT, "0", "number of frames to track across", 'f');
  op.addOption("np", OPT_INT, "0", "number of particles to use");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void particlefilter_naive(ResultDatabase &resultDB, int args[]);
///
/// @brief	Particlefilter naive
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	resultDB	The result database. 
/// @param 		   	args		The arguments. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void particlefilter_naive(ResultDatabase &resultDB, int args[]);

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void RunBenchmark(ResultDatabase &resultDB, OptionParser &op)
///
/// @brief	Executes the benchmark operation
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	resultDB	The result database. 
/// @param [in,out]	op			The operation. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void RunBenchmark(ResultDatabase &resultDB, OptionParser &op) {
    printf("Running ParticleFilter (naive)\n");
    int args[4];
    args[0] = op.getOptionInt("dimx");
    args[1] = op.getOptionInt("dimy");
    args[2] = op.getOptionInt("framecount");
    args[3] = op.getOptionInt("np");
    bool preset = false;
    verbose = op.getOptionBool("verbose");
    quiet = op.getOptionBool("quiet");

    for(int i = 0; i < 4; i++) {
        if(args[i] <= 0) {
            preset = true;
        }
    }
    if(preset) {
        int probSizes[4][4] = {{10, 10, 2, 100},
                               {40, 40, 5, 500},
                               {200, 200, 8, 500000},
                               {500, 500, 15, 1000000}};
        int size = op.getOptionInt("size") - 1;
        for(int i = 0; i < 4; i++) {
            args[i] = probSizes[size][i];
        }
    }

    if(!quiet) {
    printf("Using dimx=%d, dimy=%d, framecount=%d, numparticles=%d\n",
           args[0], args[1], args[2], args[3]);
    }

    int passes = op.getOptionInt("passes");
    for(int i = 0; i < passes; i++) {
        if(!quiet) {
            printf("Pass %d: ", i);
        }
        particlefilter_naive(resultDB, args);
        if(!quiet) {
            printf("Done.\n");
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// @fn	void particlefilter_naive(ResultDatabase &resultDB, int args[])
///
/// @brief	Particlefilter naive
///
/// @author	Ed
/// @date	5/20/2020
///
/// @param [in,out]	resultDB	The result database. 
/// @param 		   	args		The arguments. 
////////////////////////////////////////////////////////////////////////////////////////////////////

void particlefilter_naive(ResultDatabase &resultDB, int args[]){
	
	int IszX, IszY, Nfr, Nparticles;
	IszX = args[0];
	IszY = args[1];
    Nfr = args[2];
    Nparticles = args[3];

	//establish seed
#ifdef UNIFIED_MEMORY
    int *seed = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&seed, sizeof(int) * Nparticles));
#else
	int * seed = (int *)malloc(sizeof(int)*Nparticles);
#endif
	int i;
	for(i = 0; i < Nparticles; i++)
		seed[i] = time(0)*i;
	//malloc matrix
#ifdef UNIFIED_MEMORY
    int *I = NULL;
    CUDA_SAFE_CALL(cudaMallocManaged(&I, sizeof(int) * IszX * IszY * Nfr));
#else
	int * I = (int *)malloc(sizeof(int)*IszX*IszY*Nfr);
#endif
	//call video sequence
	videoSequence(I, IszX, IszY, Nfr, seed);
	//call particle filter
	particleFilter(I, IszX, IszY, Nfr, seed, Nparticles, resultDB);
	
#ifdef UNIFIED_MEMORY
    CUDA_SAFE_CALL(cudaFree(seed));
    CUDA_SAFE_CALL(cudaFree(I));
#else
	free(seed);
	free(I);
#endif
}