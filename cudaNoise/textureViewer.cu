// textureViewer
// Simple GL texture viewer to preview 2D slices of textures produced
// by cuda noise

#define GL_GLEXT_PROTOTYPES
#include <glut.h>
#include <glext.h>
#include <cuda.h>
#include <cuda_gl_interop.h>

#include <iostream>
#include <time.h>

#include "cudanoise.cuh"

#define DIM 512

uchar4 *devPtr;
dim3 blocks(DIM / 16, DIM / 16);
dim3 threads(16, 16);

float zoom = 16.0f;
int genSeed = 42;

GLuint bufferObj;
cudaGraphicsResource *resource;

__global__ void kernel(uchar4 *ptr, float zoomFactor, int samples, int seed)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x * gridDim.x;

	float fx = x / (float)DIM;
	float fy = y / (float)DIM;

	float3 pos = make_float3(fx, fy, 0.0f);
	pos = scaleVector(pos, zoomFactor);

	float acc = 0.0f;

	for (int i = 0; i < samples; i++)
	{
		float dx = getRandomValue(327482 + i * 2347 + seed)  / (float)DIM * zoomFactor - 0.5f;
		float dy = getRandomValue(912472 + i * 118438 + seed)  / (float)DIM * zoomFactor - 0.5f;
		float dz = getRandomValue(112348 + i * 68214 + seed)  / (float)DIM * zoomFactor - 0.5f;

		float3 ditheredPos = make_float3(pos.x + dx, pos.y + dy, pos.z + dz);

//		float val = checker(fx, fy, 0.0f, 64.0f);
//		float val = discreteNoise(fx, fy, 0.0f, zoomFactor);
		float val = linearValue(ditheredPos, 1.0f, seed);
//		float val = perlinNoise(ditheredPos, 1.0f, seed);
//		float val = repeater(ditheredPos, 6, 2.0f, 0.5f, CUDANOISE_PERLIN);
//		float val = turbulence(ditheredPos, 50.5f);
//		float val = repeaterTurbulence(ditheredPos, 50.5f, 16);
//		float val = recursiveTurbulence(ditheredPos, 3, 2.0f, 0.5f, 1.0f);
//		float val = recursiveRepeaterTurbulence(ditheredPos, 4, 8, 2.0f, 0.5f, 1.0f);
//		float val = cubicValue(ditheredPos, 1.0f);
//		float val = fadedValue(ditheredPos, 1.0f);

		acc += val;
	}


	acc /= (float)samples;

	acc = mapToUnsigned(acc);
	acc = clamp(acc, 0.0f, 1.0f);

	unsigned char iVal = 255 * acc;

	ptr[offset].x = iVal;
	ptr[offset].y = iVal;
	ptr[offset].z = iVal;
	ptr[offset].w = 255;
}

void setSeed(int newSeed)
{
	genSeed = newSeed;
}

void redrawTexture()
{
	cudaGraphicsMapResources(1, &resource, NULL);
	kernel << < blocks, threads >> > (devPtr, zoom *= 1.0001f, 1, genSeed);
	cudaGraphicsUnmapResources(1, &resource, NULL);

	glutPostRedisplay();
}

static void idle_func(void)
{
}

static void draw_func(void)
{
	glDrawPixels(DIM, DIM, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	glutSwapBuffers();
}

static void key_func(unsigned char key, int x, int y)
{
	switch (key)
	{
	// ESC to exit
	case 27:
		cudaGraphicsUnregisterResource(resource);
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, 0);
		glDeleteBuffers(1, &bufferObj);
		exit(0);
		break; // because fu
	// Plus to zoom in
	case 43:
		zoom *= 0.5f;
		redrawTexture();
		break;
	// Minus to zoom out
	case 45:
		zoom *= 2.0f;
		redrawTexture();
		break;
	// Spacebar to get new seed
	case 32:
		clock_t t = clock();
		unsigned int newSeed = (unsigned int)((double)t * 1000.0f);
		setSeed(newSeed);
		redrawTexture();
		break;
	}
}

int main(int argc, char **argv)
{
	cudaDeviceProp prop;
	int dev;

	setSeed(time(NULL));

	memset(&prop, 0, sizeof(cudaDeviceProp));
	prop.major = 1;
	prop.minor = 0;
	cudaChooseDevice(&dev, &prop);

	cudaGLSetGLDevice(dev);

	glutInit(&argc, argv);
	glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA);
	glutInitWindowSize(DIM, DIM);
	glutCreateWindow("cudaNoise - Texture Viewer");

	glGenBuffers(1, &bufferObj);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, bufferObj);
	glBufferData(GL_PIXEL_UNPACK_BUFFER_ARB, DIM * DIM * 4, NULL, GL_DYNAMIC_DRAW_ARB);

	cudaGraphicsGLRegisterBuffer(&resource, bufferObj, cudaGraphicsMapFlagsNone);

	size_t size;
	cudaGraphicsMapResources(1, &resource, NULL);
	cudaGraphicsResourceGetMappedPointer((void**)&devPtr, &size, resource);

	kernel << <blocks, threads >> > (devPtr, zoom, 1, genSeed);

	cudaGraphicsUnmapResources(1, &resource, NULL);

	glutIdleFunc(idle_func);
	glutKeyboardFunc(key_func);
	glutDisplayFunc(draw_func);
	glutMainLoop();
}