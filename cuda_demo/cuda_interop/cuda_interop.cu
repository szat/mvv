////////////////////////////////////////////////////////////////////////////
//
// Copyright 1993-2015 NVIDIA Corporation.  All rights reserved.
//
// Please refer to the NVIDIA end user license agreement (EULA) associated
// with this source code for terms and conditions that govern your use of
// this software. Any use, reproduction, disclosure, or distribution of
// this software and related documentation outside the terms of the EULA
// is strictly prohibited.
//
////////////////////////////////////////////////////////////////////////////

/*
This example demonstrates how to use the Cuda OpenGL bindings to
dynamically modify a vertex buffer using a Cuda kernel.

The steps are:
1. Create an empty vertex buffer object (VBO)
2. Register the VBO with Cuda
3. Map the VBO for writing from Cuda
4. Run Cuda kernel to modify the vertex positions
5. Unmap the VBO
6. Render the results using OpenGL

Host code
*/

// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <ctime>

#ifdef _WIN32
#  define WINDOWS_LEAN_AND_MEAN
#  define NOMINMAX
#  include <windows.h>
#endif

// OpenGL Graphics includes
#include <helper_gl.h>
#include <GL/freeglut.h>

// includes, cuda
#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_gl_interop.h>

// Utilities and timing functions
#include <helper_functions.h>    // includes cuda.h and cuda_runtime_api.h
#include <timer.h>               // timing functions

// CUDA helper functions
#include <helper_cuda.h>         // helper functions for CUDA error check
#include <helper_cuda_gl.h>      // helper functions for CUDA/GL interop

#include <vector_types.h>
#include <string>

using namespace cv;
using namespace std;

#define WIDTH 667 //size of david_1.jpg
#define HEIGHT 1000
#define REFRESH_DELAY     2 //ms

//TRY TO CALL GLUTPOSTREDISPLAY FROM A FOOR LOOP

GLuint  bufferObj;
cudaGraphicsResource *resource;
__device__ int counter;
__device__ volatile int param = 50;

__global__ void kernel(uchar4 *ptr, uchar4* d_img_ptr, int w, int h, int param) {
	// map from threadIdx/BlockIdx to pixel position
	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;
	if ((r >= h) || (c >= w)) return;

	// accessing uchar4 vs unsigned char*
	ptr[i].x = (d_img_ptr[i].x + param) % 255;
	ptr[i].y = d_img_ptr[i].y;
	ptr[i].z = (d_img_ptr[i].z + param) % 200;
	ptr[i].w = d_img_ptr[i].w;
}

__global__ void kernel_2(uchar4 *ptr, int w, int h, int param) {
	// map from threadIdx/BlockIdx to pixel position
	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;
	if ((r >= h) || (c >= w)) return;

	//atomicAdd(&counter, 1);

	// accessing uchar4 vs unsigned char*
	ptr[i].x = ptr[i].x + 10;
	ptr[i].y = ptr[i].y;
	ptr[i].z = ptr[i].z + 10;
	ptr[i].w = ptr[i].w;
}

static void key_func(unsigned char key, int x, int y) {
	switch (key) {
	case 27:
		// clean up OpenGL and CUDA
		cudaGraphicsUnregisterResource(resource);
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, 0);
		glDeleteBuffers(1, &bufferObj);
		exit(0);
	}
}

static void draw_func(void) {
	// we pass zero as the last parameter, because out bufferObj is now
	// the source, and the field switches from being a pointer to a
	// bitmap to now mean an offset into a bitmap object

	glDrawPixels(WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	glutSwapBuffers();
}

void timerEvent(int value)
{
	if (glutGetWindow())
	{
		glutPostRedisplay();
		glutTimerFunc(REFRESH_DELAY, timerEvent, 0);
	}
}

int main(int argc, char **argv)
{
	string img_path = "../../data_store/images/david_1.jpg";
	Mat img = imread(img_path, IMREAD_COLOR);
	int H = img.size().height;
	int W = img.size().width;

	Mat bgra;
	cvtColor(img, bgra, CV_BGR2BGRA);
	uchar4* h_img_ptr = new uchar4[WIDTH * HEIGHT * sizeof(uchar4)];
	for (int i = 0; i < WIDTH * HEIGHT * sizeof(uchar4); i++) {
		uchar4 tester;
		tester.x = 255;
		tester.y = 0;
		tester.z = 0;
		tester.w = 0;
		h_img_ptr[i] = tester;
	}

	//h_img_ptr = (uchar4*)(bgra.data);
	uchar4* d_img_ptr;
	cudaMalloc((void**)&d_img_ptr, WIDTH*HEIGHT * sizeof(uchar4));
	cudaMemcpy(d_img_ptr, h_img_ptr, WIDTH*HEIGHT * sizeof(uchar4), cudaMemcpyHostToDevice);


	cudaDeviceProp  prop;
	int dev;

	memset(&prop, 0, sizeof(cudaDeviceProp));
	prop.major = 1;
	prop.minor = 0;
	cudaChooseDevice(&dev, &prop);

	// tell CUDA which dev we will be using for graphic interop
	// from the programming guide:  Interoperability with OpenGL
	//     requires that the CUDA device be specified by
	//     cudaGLSetGLDevice() before any other runtime calls.


	cudaGLSetGLDevice(dev);

	// these GLUT calls need to be made before the other OpenGL
	// calls, else we get a seg fault
	glutInit(&argc, argv);
	glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA);
	glutInitWindowSize(WIDTH, HEIGHT);
	glutCreateWindow("bitmap");
	glutTimerFunc(REFRESH_DELAY, timerEvent, 0);

	//not in tutorial, otherwise crashes
	if (GLEW_OK != glewInit()) { return 1; }
	while (GL_NO_ERROR != glGetError());

	// the first three are standard OpenGL, the 4th is the CUDA reg 
	// of the bitmap these calls exist starting in OpenGL 1.5
	glGenBuffers(1, &bufferObj);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, bufferObj);
	glBufferData(GL_PIXEL_UNPACK_BUFFER_ARB, WIDTH * HEIGHT * sizeof(uchar4), NULL, GL_DYNAMIC_DRAW_ARB);

	glutKeyboardFunc(key_func);
	//which one to pick? goes along with postrediplay
	//glutIdleFunc(draw_func);
	glutDisplayFunc(draw_func);

	cudaGraphicsGLRegisterBuffer(&resource, bufferObj, cudaGraphicsMapFlagsNone);

	cudaGraphicsMapResources(1, &resource, NULL);

	uchar4* devPtr;
	size_t  size;

	cudaGraphicsResourceGetMappedPointer((void**)&devPtr, &size, resource);

	dim3 blockSize(32, 32);
	int bx = (WIDTH + 32 - 1) / 32;
	int by = (HEIGHT + 32 - 1) / 32;
	dim3 gridSize = dim3(bx, by);
	kernel << <gridSize, blockSize >> >(devPtr, d_img_ptr, WIDTH, HEIGHT, param);

	cudaGraphicsUnmapResources(1, &resource, NULL);

	/*
	int addXdir = 1;
	int * devAddXdir;
	cudaMalloc((void**)&devAddXdir, sizeof(int));
	cudaMemcpy(devAddXdir, &addXdir, sizeof(int), cudaMemcpyHostToDevice);
	*/

	for (;;) {
		/*
		string img_path = "../../data_store/images/david_1.jpg";
		Mat img = imread(img_path, IMREAD_COLOR);
		int H = img.size().height;
		int W = img.size().width;
		Mat bgra;
		cvtColor(img, bgra, CV_BGR2BGRA);
		*/
		
		uchar4* h_img_ptr = new uchar4[WIDTH * HEIGHT];
		for (int i = 0; i < WIDTH * HEIGHT; i++) {
			h_img_ptr[i].x = 255;
			h_img_ptr[i].y = 0;
			h_img_ptr[i].z = 0;
		}

		h_img_ptr = (uchar4*)(bgra.data);

		dim3 blockSize(32, 32);
		int bx = (WIDTH + 32 - 1) / 32;
		int by = (HEIGHT + 32 - 1) / 32;
		dim3 gridSize = dim3(bx, by);

		cudaGraphicsMapResources(1, &resource, NULL);

		uchar4* devPtr;
		size_t  size;

		cudaGraphicsResourceGetMappedPointer((void**)&devPtr, &size, resource);

		kernel_2 << <gridSize, blockSize >> >(devPtr, WIDTH, HEIGHT, 0);

		cudaGraphicsUnmapResources(1, &resource, NULL);


		//Does not seem "necessary"
		cudaDeviceSynchronize();

		//only gluMainLoopEvent() seems necessary
		glutPostRedisplay();
		glutMainLoopEvent();
	}

	// set up GLUT and kick off main loop
	glutMainLoop();

}