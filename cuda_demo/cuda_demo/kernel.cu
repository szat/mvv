#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>

#include <string>
#include <stdio.h>
#include <iostream>
#include <cuda.h>
#include <conio.h>
#include <ctime>
#include <chrono>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include "binary_io.h"

using namespace std;
using namespace cv;

typedef std::chrono::high_resolution_clock Clock;

__global__
void kernel2D(uchar* d_output, uchar* d_input, int w, int h, float * d_affineData)
{
	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;

	if ((r >= h) || (c >= w)) return;

	int new_c = (int)(d_affineData[0] * (float)c + d_affineData[1] * (float)r + d_affineData[2]);
	int new_r = (int)(d_affineData[3] * (float)c + d_affineData[4] * (float)r + d_affineData[5]);

	if ((new_r >= h) || (new_c >= w) || (new_r < 0) || (new_c < 0)) return;

	int new_i = new_r * w + new_c;
	d_output[new_i] = d_input[i];
}

__global__
void kernel2D_subpix(uchar* d_output, uchar* d_input, short* d_raster1, int w, int h, float * d_affineData, int subDiv, float tau, bool reverse)
{
	if (tau >= 1 || tau < 0) return;

	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;
	uchar input = d_input[i];

	if ((r >= h) || (c >= w)) return;

	short affine_index = d_raster1[i];
	short offset = affine_index * 12;
	if (reverse) {
		offset += 6;
	}
	if (affine_index != 0) {
		float diff = 1 / (float)subDiv;
		for (int i = 0; i < subDiv; i++) {
			for (int j = 0; j < subDiv; j++) {
				int new_c = (int)(((1-tau) + tau*d_affineData[offset]) * (float)(c - 0.5 + (diff * i)) + (tau * d_affineData[offset + 1]) * (float)(r - 0.5 + (diff * j)) + (tau * d_affineData[offset + 2]));
				int new_r = (int)((tau * d_affineData[offset + 3]) * (float)(c - 0.5 + (diff * i)) + ((1-tau) + tau * d_affineData[offset + 4]) * (float)(r - 0.5 + (diff * j)) + (tau * d_affineData[offset + 5]));
				if ((new_r >= h) || (new_c >= w) || (new_r < 0) || (new_c < 0)) return;
				int new_i = new_r * w + new_c;
				d_output[new_i] = input;
			}
		}
	}
}

__global__
void kernel2D_subpix_color(uchar* d_output, uchar* d_input, short* d_raster1, int w, int h, float * d_affineData, int subDiv, float tau, bool reverse)
{
	if (tau >= 1 || tau < 0) return;

	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;
	uchar input = d_input[i];

	if ((r >= h) || (c >= w)) return;

	short affine_index = d_raster1[i];
	short offset = affine_index * 12;
	if (reverse) {
		offset += 6;
	}
	if (affine_index != 0) {
		float diff = 1 / (float)subDiv;
		for (int i = 0; i < subDiv; i++) {
			for (int j = 0; j < subDiv; j++) {
				int new_c = (int)(((1 - tau) + tau*d_affineData[offset]) * (float)(c - 0.5 + (diff * i)) + (tau * d_affineData[offset + 1]) * (float)(r - 0.5 + (diff * j)) + (tau * d_affineData[offset + 2]));
				int new_r = (int)((tau * d_affineData[offset + 3]) * (float)(c - 0.5 + (diff * i)) + ((1 - tau) + tau * d_affineData[offset + 4]) * (float)(r - 0.5 + (diff * j)) + (tau * d_affineData[offset + 5]));
				if ((new_r >= h) || (new_c >= w) || (new_r < 0) || (new_c < 0)) return;
				int new_i = new_r * w + new_c;
				d_output[new_i] = input;
			}
		}
	}
}

__global__
void kernel2D_add(uchar* d_output, uchar* d_input_1, uchar* d_input_2, int w, int h, float tau) {
	//tau is from a to b
	int c = blockIdx.x*blockDim.x + threadIdx.x;
	int r = blockIdx.y*blockDim.y + threadIdx.y;
	int i = r * w + c;

	if ((r >= h) || (c >= w)) return;

	if (d_input_1[i] == 0) {
		d_output[i] = d_input_2[i];
	}
	else if (d_input_2[i] == 0) {
		d_output[i] = d_input_1[i];
	}
	else {
		d_output[i] = tau*d_input_1[i] + (1-tau)*d_input_2[i];
	}
}

int color_display() {
	// Initializing CUDA
	uchar *h_tester = new uchar[1];
	h_tester[0] = (uchar)0;
	uchar *d_tester;
	cudaMalloc((void**)&d_tester, sizeof(uchar));
	cudaMemcpy(d_tester, h_tester, sizeof(uchar), cudaMemcpyHostToDevice);
	cudaFree(d_tester);

	auto t1 = std::chrono::high_resolution_clock::now();

	string img1_path = "../../data_store/images/david_1.jpg";
	string img2_path = "../../data_store/images/david_2.jpg";

	Mat img_color_1 = imread(img1_path, CV_LOAD_IMAGE_COLOR);
	Mat img_color_2 = imread(img2_path, CV_LOAD_IMAGE_COLOR);

	Size desired_size = img_color_2.size();
	resize(img_color_1, img_color_1, desired_size);

	Mat channel_img_1[3];
	Mat channel_img_2[3];
	split(img_color_1, channel_img_1);
	split(img_color_2, channel_img_2);



	//channel_img_1[0] = Mat::zeros(img_color_1.rows, img_color_1.cols, CV_8UC1);
	//channel_img_1[1] = Mat::zeros(img_color_1.rows, img_color_1.cols, CV_8UC1);

	string raster1_path = "../../data_store/raster/rasterA.bin";
	string raster2_path = "../../data_store/raster/rasterB.bin";

	int num_pixels_1 = 0;
	int num_pixels_2 = 0;
	// look into this memory allocation later
	short *h_raster1 = read_short_array(raster1_path, num_pixels_1);
	short *h_raster2 = read_short_array(raster2_path, num_pixels_2);

	string affine_path = "../../data_store/affine/affine_1.bin";

	int num_floats = 0;
	float *h_affine_data = read_float_array(affine_path, num_floats);

	int num_triangles = num_floats / 12;


	int W = img_color_1.size().width;
	int H = img_color_1.size().height;

	uchar *h_img_1_in_B;
	uchar *h_img_1_in_G;
	uchar *h_img_1_in_R;
	uchar *h_img_1_out_B;
	uchar *h_img_1_out_G;
	uchar *h_img_1_out_R;
	uchar *h_img_2_in_B;
	uchar *h_img_2_in_G;
	uchar *h_img_2_in_R;
	uchar *h_img_2_out_B;
	uchar *h_img_2_out_G;
	uchar *h_img_2_out_R;
	uchar *h_img_sum_B;
	uchar *h_img_sum_G;
	uchar *h_img_sum_R;

	h_img_1_in_B = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_1_in_G = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_1_in_R = (uchar*)malloc(W*H * sizeof(uchar));
	Mat img_1_B_flat = channel_img_1[0].reshape(1, 1);
	Mat img_1_G_flat = channel_img_1[1].reshape(1, 1);
	Mat img_1_R_flat = channel_img_1[2].reshape(1, 1);
	h_img_1_in_B = img_1_B_flat.data;
	h_img_1_in_G = img_1_G_flat.data;
	h_img_1_in_R = img_1_R_flat.data;

	h_img_1_out_B = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_1_out_G = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_1_out_R = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_img_1_out_B[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_1_out_G[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_1_out_R[j] = 0;


	h_img_2_in_B = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_2_in_G = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_2_in_R = (uchar*)malloc(W*H * sizeof(uchar));
	Mat img_2_B_flat = channel_img_2[0].reshape(1, 1);
	Mat img_2_G_flat = channel_img_2[1].reshape(1, 1);
	Mat img_2_R_flat = channel_img_2[2].reshape(1, 1);
	h_img_2_in_B = img_1_B_flat.data;
	h_img_2_in_G = img_1_G_flat.data;
	h_img_2_in_R = img_1_R_flat.data;

	h_img_2_out_B = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_2_out_G = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_2_out_R = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_img_2_out_B[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_2_out_G[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_2_out_R[j] = 0;


	h_img_sum_B = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_sum_G = (uchar*)malloc(W*H * sizeof(uchar));
	h_img_sum_R = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_img_sum_B[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_sum_G[j] = 0;
	for (int j = 0; j < W*H; j++) h_img_sum_R[j] = 0;


	float * d_affine_data;
	cudaMalloc((void**)&d_affine_data, num_floats * sizeof(float));
	cudaMemcpy(d_affine_data, h_affine_data, num_floats * sizeof(float), cudaMemcpyHostToDevice);

	short *d_raster1;
	cudaMalloc((void**)&d_raster1, W * H * sizeof(short));
	cudaMemcpy(d_raster1, h_raster1, W * H * sizeof(short), cudaMemcpyHostToDevice);

	short *d_raster2;
	cudaMalloc((void**)&d_raster2, W * H * sizeof(short));
	cudaMemcpy(d_raster2, h_raster2, W * H * sizeof(short), cudaMemcpyHostToDevice);

	uchar * d_img_1_in_B;
	uchar * d_img_1_in_G;
	uchar * d_img_1_in_R;
	cudaMalloc((void**)&d_img_1_in_B, W*H * sizeof(uchar));
	cudaMalloc((void**)&d_img_1_in_G, W*H * sizeof(uchar));
	cudaMalloc((void**)&d_img_1_in_R, W*H * sizeof(uchar));
	cudaMemcpy(d_img_1_in_B, h_img_1_in_B, W*H * sizeof(uchar), cudaMemcpyHostToDevice);
	cudaMemcpy(d_img_1_in_G, h_img_1_in_G, W*H * sizeof(uchar), cudaMemcpyHostToDevice);
	cudaMemcpy(d_img_1_in_R, h_img_1_in_R, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	uchar * d_img_1_out_B;
	uchar * d_img_1_out_G;
	uchar * d_img_1_out_R;
	cudaMalloc((void**)&d_img_1_out_B, W*H * sizeof(uchar));
	cudaMalloc((void**)&d_img_1_out_G, W*H * sizeof(uchar));
	cudaMalloc((void**)&d_img_1_out_R, W*H * sizeof(uchar));
	cudaMemcpy(d_img_1_out_B, d_img_1_out_B, W*H * sizeof(uchar), cudaMemcpyHostToDevice);
	cudaMemcpy(d_img_1_out_G, d_img_1_out_G, W*H * sizeof(uchar), cudaMemcpyHostToDevice);
	cudaMemcpy(d_img_1_out_R, d_img_1_out_R, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	//--GPU variables
	dim3 blockSize(32, 32);
	int bx = (W + 32 - 1) / 32;
	int by = (H + 32 - 1) / 32;
	dim3 gridSize = dim3(bx, by);

	float tau = 0.5f;
	float reverse_tau = 1.0f - tau;
	int reversal_offset = 0;

	kernel2D_subpix_color<<<gridSize, blockSize >>>(d_img_1_out_B, d_img_1_in_B, d_raster1, W, H, d_affine_data, 4, tau, false);
	kernel2D_subpix_color<<<gridSize, blockSize >>>(d_img_1_out_G, d_img_1_in_G, d_raster1, W, H, d_affine_data, 4, tau, false);
	kernel2D_subpix_color<<<gridSize, blockSize >>>(d_img_1_out_R, d_img_1_in_R, d_raster1, W, H, d_affine_data, 4, tau, false);

	cudaMemcpy(h_img_1_out_B, d_img_1_out_B, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);
	cudaMemcpy(h_img_1_out_G, d_img_1_out_G, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);
	cudaMemcpy(h_img_1_out_R, d_img_1_out_R, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);

	Mat img1_B = Mat(1, W*H, CV_8UC1, h_img_1_out_B);
	Mat img1_G = Mat(1, W*H, CV_8UC1, h_img_1_out_G);
	Mat img1_R = Mat(1, W*H, CV_8UC1, h_img_1_out_R);
	img1_B = img1_B.reshape(1, H);
	img1_G = img1_G.reshape(1, H);
	img1_R = img1_R.reshape(1, H);

	/*
	Mat img1_post_B = Mat(1, W*H, CV_8UC1, h_img_1_in_B);
	Mat img1_post_G = Mat(1, W*H, CV_8UC1, h_img_1_in_G);
	Mat img1_post_R = Mat(1, W*H, CV_8UC1, h_img_1_in_R);
	img1_post_B = img1_post_B.reshape(1, H);
	img1_post_G = img1_post_B.reshape(1, H);
	img1_post_R = img1_post_B.reshape(1, H);
	*/



	Mat final_channel_1[3];
	final_channel_1[0] = img1_B;
	final_channel_1[1] = img1_G;
	final_channel_1[2] = img1_R;

	merge(final_channel_1, 3, img_color_1);
	
	auto t2 = std::chrono::high_resolution_clock::now();
	std::cout << "write short took "
		<< std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count()
		<< " milliseconds\n";

	return -1;
}

int main(int argc, char ** argv) {
	cout << "welcome to cuda_demo testing unit!" << endl;
	cout << "loading 2 images with openCV, processing and adding them with cuda (grayscale)." << endl;

	color_display();

	string img1_path = "../../data_store/images/david_1.jpg";
	string img2_path = "../../data_store/images/david_2.jpg";
	Mat img1 = imread(img1_path, IMREAD_GRAYSCALE);
	Mat img2 = imread(img2_path, IMREAD_GRAYSCALE);

	Size desiredSize = img2.size();
	resize(img1, img1, desiredSize);

	string raster1_path = "../../data_store/raster/rasterA.bin";
	string raster2_path = "../../data_store/raster/rasterB.bin";

	// Initializing CUDA
	uchar *h_tester = new uchar[1];
	h_tester[0] = (uchar)0;
	uchar *d_tester;
	cudaMalloc((void**)&d_tester, sizeof(uchar));
	cudaMemcpy(d_tester, h_tester, sizeof(uchar), cudaMemcpyHostToDevice);
	cudaFree(d_tester);

	auto t1 = std::chrono::high_resolution_clock::now();

	int num_pixels_1 = 0;
	int num_pixels_2 = 0;
	// look into this memory allocation later
	short *h_raster1 = read_short_array(raster1_path, num_pixels_1);
	short *h_raster2 = read_short_array(raster2_path, num_pixels_2);

	string affine_path = "../../data_store/affine/affine_1.bin";

	int num_floats = 0;
	float *h_affine_data = read_float_array(affine_path, num_floats);

	int num_triangles = num_floats / 12;


	int W = img1.size().width;
	int H = img1.size().height;

	cout << "declaring host data-structures..." << endl;
	uchar *h_img1In;
	uchar *h_img1Out;
	uchar *h_img2In;
	uchar *h_img2Out;
	uchar *h_imgSum;
	
	h_img1In = (uchar*)malloc(W*H * sizeof(uchar));
	Mat img1Flat = img1.reshape(1, 1);
	h_img1In = img1Flat.data;

	h_img1Out = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_img1Out[j] = 0;

	h_img2In = (uchar*)malloc(W*H * sizeof(uchar));
	Mat img2Flat = img2.reshape(1, 1);
	h_img2In = img2Flat.data;

	h_img2Out = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_img2Out[j] = 0;

	h_imgSum = (uchar*)malloc(W*H * sizeof(uchar));
	for (int j = 0; j < W*H; j++) h_imgSum[j] = 0;

	//--Sending the data to the GPU memory
	cout << "declaring device data-structures..." << endl;

	float * d_affine_data;
	cudaMalloc((void**)&d_affine_data, num_floats * sizeof(float));
	cudaMemcpy(d_affine_data, h_affine_data, num_floats * sizeof(float), cudaMemcpyHostToDevice);

	short *d_raster1;
	cudaMalloc((void**)&d_raster1, W * H * sizeof(short));
	cudaMemcpy(d_raster1, h_raster1, W * H * sizeof(short), cudaMemcpyHostToDevice);

	short *d_raster2;
	cudaMalloc((void**)&d_raster2, W * H * sizeof(short));
	cudaMemcpy(d_raster2, h_raster2, W * H * sizeof(short), cudaMemcpyHostToDevice);

	uchar * d_img1In;
	cudaMalloc((void**)&d_img1In, W*H * sizeof(uchar));
	cudaMemcpy(d_img1In, h_img1In, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	uchar * d_img1Out;
	cudaMalloc((void**)&d_img1Out, W*H * sizeof(uchar));
	cudaMemcpy(d_img1Out, h_img1Out, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	uchar * d_img2In;
	cudaMalloc((void**)&d_img2In, W*H * sizeof(uchar));
	cudaMemcpy(d_img2In, h_img2In, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	uchar * d_img2Out;
	cudaMalloc((void**)&d_img2Out, W*H * sizeof(uchar));
	cudaMemcpy(d_img2Out, h_img2Out, W*H * sizeof(uchar), cudaMemcpyHostToDevice);

	uchar * d_imgSum;
	cudaMalloc((void**)&d_imgSum, W*H * sizeof(uchar));
	cudaMemcpy(d_imgSum, h_imgSum, W*H * sizeof(uchar), cudaMemcpyHostToDevice);




	//--GPU variables
	dim3 blockSize(32, 32);
	int bx = (W + 32 - 1) / 32;
	int by = (H + 32 - 1) / 32;
	dim3 gridSize = dim3(bx, by);

	float tau = 0.5f;
	float reverse_tau = 1.0f - tau;
	int reversal_offset = 0;

	

	kernel2D_subpix << <gridSize, blockSize >> >(d_img1Out, d_img1In, d_raster1, W, H, d_affine_data, 4, tau, false);
	kernel2D_subpix << <gridSize, blockSize >> >(d_img2Out, d_img2In, d_raster2, W, H, d_affine_data, 4, reverse_tau, true);
	kernel2D_add << <gridSize, blockSize >> > (d_imgSum, d_img1Out, d_img2Out, W, H, tau);



	cudaMemcpy(h_img1Out, d_img1Out, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);
	cudaMemcpy(h_img2Out, d_img2Out, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);
	cudaMemcpy(h_imgSum, d_imgSum, W*H * sizeof(uchar), cudaMemcpyDeviceToHost);

	cudaFree(d_img1In);
	cudaFree(d_img1Out);
	cudaFree(d_affine_data);
	cudaFree(d_img2In);
	cudaFree(d_img2Out);
	cudaFree(d_affine_data);
	cudaFree(d_imgSum);

	auto t2 = std::chrono::high_resolution_clock::now();
	std::cout << "write short took "
		<< std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count()
		<< " milliseconds\n";

	Mat render1 = Mat(1, W*H, CV_8UC1, h_img1Out);
	render1 = render1.reshape(1, H);

	Mat render2 = Mat(1, W*H, CV_8UC1, h_img2Out);
	render2 = render2.reshape(1, H);

	Mat renderSum = Mat(1, W*H, CV_8UC1, h_imgSum);
	renderSum = renderSum.reshape(1, H);

	return 0;
}