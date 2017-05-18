#include "binary_io.h"
#include <iostream>
#include <fstream>
#include <chrono>
#include <string>

using namespace std;
using namespace cv;
// Note about all of this:
// OS-dependent! This will not work on other architectures (for now).


void write_char_array(string full_path, char * input, int length) {
	ofstream ofile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	int_array[0] = length;
	memcpy(length_array, int_array, 4);
	ofile.write(length_array, 4);
	ofile.write(input, length);
	ofile.close();
}

char * read_char_array(string full_path, int &length) {
	// modifies length, returns char array
	ifstream ifile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	ifile.read(length_array, 4);
	memcpy(int_array, length_array, 4);
	length = int_array[0];
	char * result = new char[length];
	ifile.read(result, length);
	return result;
}

void write_short_array(string full_path, short * input, int length) {
	char * char_input = new char[length * 2];
	ofstream ofile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	int_array[0] = length;
	memcpy(length_array, int_array, 4);
	ofile.write(length_array, 4);
	memcpy(char_input, input, length * 2);
	ofile.write(length_array, 4);
	ofile.write(char_input, length * 2);
}

short * read_short_array(string full_path, int &length) {
	ifstream ifile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	ifile.read(length_array, 4);
	memcpy(int_array, length_array, 4);
	length = int_array[0];
	char * result = new char[length * 2];
	ifile.read(result, length * 2);
	short * short_result = new short[length];
	memcpy(short_result, result, length * 2);
	return short_result;
}

void write_float_array(string full_path, float * input, int length) {
	char * char_input = new char[length * 4];
	ofstream ofile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	int_array[0] = length;
	memcpy(length_array, int_array, 4);
	ofile.write(length_array, 4);
	memcpy(char_input, input, length * 4);
	ofile.write(char_input, length * 4);
}

float * read_float_array(string full_path, int &length) {
	ifstream ifile(full_path, ios::binary);
	char * length_array = new char[4];
	int * int_array = new int[1];
	ifile.read(length_array, 4);
	memcpy(int_array, length_array, 4);
	length = int_array[0];
	float * result = new float[length];
	char * char_result = new char[length * 4];
	ifile.read(char_result, length * 4);
	memcpy(result, char_result, length * 4);
	return result;
}

void save_raster(string full_path, short ** raster, int width, int height) {
	int size = width * height;
	short * raster_1D = new short[size];
	for (int i = 0; i < height; i++) {
		for (int j = 0; j < width; j++) {
			raster_1D[i * width + j] = raster[i][j];
		}
	}
	write_short_array(full_path, raster_1D, size);
}

float* convert_vector_params(vector<Mat> forward_params, vector<Mat> reverse_params) {
	int num_triangles = forward_params.size();
	float* params = new float[num_triangles * 12];
	for (int i = 0; i < num_triangles; i++) {
		int inc = 12 * i;
		params[inc] = (float)forward_params[i].at<double>(0, 0);
		params[inc + 1] = (float)forward_params[i].at<double>(0, 1);
		params[inc + 2] = (float)forward_params[i].at<double>(0, 2);
		params[inc + 3] = (float)forward_params[i].at<double>(1, 0);
		params[inc + 4] = (float)forward_params[i].at<double>(1, 1);
		params[inc + 5] = (float)forward_params[i].at<double>(1, 2);
		params[inc + 6] = (float)reverse_params[i].at<double>(0, 0);
		params[inc + 7] = (float)reverse_params[i].at<double>(0, 1);
		params[inc + 8] = (float)reverse_params[i].at<double>(0, 2);
		params[inc + 9] = (float)reverse_params[i].at<double>(1, 0);
		params[inc + 10] = (float)reverse_params[i].at<double>(1, 1);
		params[inc + 11] = (float)reverse_params[i].at<double>(1, 2);
	}
	return params;
}