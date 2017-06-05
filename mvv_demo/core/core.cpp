// core.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"

#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <vector>
#include <ctime>
#include <stdlib.h>
#include <iostream>
#include <chrono>
#include <fstream>

#include "binary_write.h"
#include "merge_background.h"
#include "flash_detection.h"

#include "build_geometry.h"
#include "generate_test_points.h"

#include "match_points.h"
#include "good_features.h"
#include "affine_akaze.h"
#include "knn_test.h"
#include "background_substraction.h"

#include "interpolate_images.h"
#include "polygon_raster.h"


#define VERSION "1.0.0"
#define APPLICATION_NAME "MVV"
#define COMPANY_NAME "NDim Inc."
#define COPYRIGHT_YEAR 2017
#define CLOCKS_PER_MS (CLOCKS_PER_SEC / 1000)
#define NUM_THREADS 16

typedef std::chrono::high_resolution_clock Clock;

using namespace std;
using namespace cv;

int corner_points_test() {
	cout << "Begin integration test of match_features and build_geometry" << endl;

	//this is the image used in trackbarCorners
	string image_path = "..\\data_store\\david_1.jpg";
	Mat src1 = imread(image_path, IMREAD_GRAYSCALE); 
	vector<Point2f> corners;
	trackbar_corners(image_path, corners);


	Rect test_rect = Rect(0, 0, src1.size().width, src1.size().height);
	graphical_triangulation(corners, test_rect);

	return 0;
}

Rect get_image_size(string imagePath) {
	string address = "..\\data_store\\" + imagePath;
	string input = "";
	ifstream infile1;
	infile1.open(address.c_str());

	Mat img1 = imread(address, IMREAD_GRAYSCALE);

	float height = img1.size().height;
	float width = img1.size().width;

	Rect image_size = Rect(0, 0, width, height);
	return image_size;
}

int test_matching() {

	string imageA = "david_1.jpg";
	string imageB = "david_2.jpg";

	Rect image_size_A = get_image_size(imageA);
	Rect image_size_B = get_image_size(imageB);

	vector<vector<KeyPoint>> point_matches = test_match_points(imageA, imageB);

	vector<KeyPoint> image_matchesA = point_matches.at(0);
	vector<KeyPoint> image_matchesB = point_matches.at(1);

	vector<Point2f> image_pointsA = vector<Point2f>();

	int vecSize = image_matchesA.size();

	for (int i = 0; i < vecSize; i++) {
		image_pointsA.push_back(image_matchesA.at(i).pt);
	}

	//graphical_triangulation(imagePointsA, imageSizeA);
	//Subdiv2D subdiv = raw_triangulation(imagePointsA, imageSizeA);
	//display_triangulation(subdiv, imageSizeA);

	return 0;
}

struct GeometricSlice {
	Rect img;
	vector<Vec6f> triangles;
};

struct MatchedGeometry {
	GeometricSlice source_geometry;
	GeometricSlice target_geometry;
};

MatchedGeometry create_matched_geometry(vector<Point2f> imgA_points, vector<Point2f> imgB_points, Size size) {
	// triangulate source interior
	vector<Vec6f> trianglesA = construct_triangles(imgA_points, size);

	// triangulate target interior
	vector<Vec6f> trianglesB = triangulate_target(imgA_points, imgB_points, trianglesA);

	Rect img_bounds = Rect(0, 0, size.width, size.height);

	// This could potentially be replaced by two constructors.
	MatchedGeometry matched_result = MatchedGeometry();
	GeometricSlice source = GeometricSlice();
	GeometricSlice target = GeometricSlice();
	source.triangles = trianglesA;
	target.triangles = trianglesB;
	source.img = img_bounds;
	target.img = img_bounds;
	matched_result.source_geometry = source;
	matched_result.target_geometry = target;
	return matched_result;
}

MatchedGeometry read_matched_points_from_file(string img1_path, string img2_path) {
	// Please note that:
	// A: source image
	// B: target image
	// I use this shorthand so that the variable names are shorter.

	cout << "Initializing matched geometry routine" << endl;

	//string imgA_path = source_path;
	//string imgB_path = target_path;
	//string root_path = "../data_store";
	Mat imgA = cv::imread(img1_path, IMREAD_GRAYSCALE);
	Mat imgB = cv::imread(img2_path, IMREAD_GRAYSCALE);

	Size desired_size = imgB.size();
	resize(imgA, imgA, desired_size);

	vector<vector<KeyPoint>> point_matches = match_points_mat(imgA, imgB);

	vector<KeyPoint> imgA_keypoints = point_matches[0];
	vector<KeyPoint> imgB_keypoints = point_matches[1];
	vector<Point2f> imgA_points = convert_key_points(imgA_keypoints);
	vector<Point2f> imgB_points = convert_key_points(imgB_keypoints);

	MatchedGeometry geometry = create_matched_geometry(imgA_points, imgB_points, desired_size);
	return geometry;
}

void render_matched_geometry(GeometricSlice slice, string window_name) {
	// Render both images.

	// Trapezoids in red (first)
	Mat img(slice.img.size(), CV_8UC3);
	Scalar trapezoid_color(0, 0, 255), triangle_color(255, 255, 255), hull_color(255, 0, 0);
	string win = window_name;

	vector<Point> pt(3);
	int num_triangles = slice.triangles.size();
	for (int i = 0; i < num_triangles; i++) {
		Vec6f t = slice.triangles[i];
		pt[0] = Point(cvRound(t[0]), cvRound(t[1]));
		pt[1] = Point(cvRound(t[2]), cvRound(t[3]));
		pt[2] = Point(cvRound(t[4]), cvRound(t[5]));
		line(img, pt[0], pt[1], triangle_color, 1, LINE_AA, 0);
		line(img, pt[1], pt[2], triangle_color, 1, LINE_AA, 0);
		line(img, pt[2], pt[0], triangle_color, 1, LINE_AA, 0);
	}

	imshow(win, img);
	waitKey(1);
	// Triangles in white (second)
	// Border (convex hull in blue) (last)
}

void save_frame_master(string img1_path, string img2_path) {
	MatchedGeometry geometry = read_matched_points_from_file(img1_path, img2_path);

	vector<Vec6f> trianglesA = geometry.source_geometry.triangles;
	vector<Vec6f> trianglesB = geometry.target_geometry.triangles;
	
	Rect imgA_bounds = geometry.source_geometry.img;
	Rect imgB_bounds = geometry.target_geometry.img;

	vector<vector<Point>> rastered_trianglesA = raster_triangulation(trianglesA, imgA_bounds);
	vector<vector<Point>> rastered_trianglesB = raster_triangulation(trianglesB, imgB_bounds);

	int widthA = imgA_bounds.width;
	int heightA = imgA_bounds.height;
	int widthB = imgB_bounds.width;
	int heightB = imgB_bounds.height;

	// save affine params as .csv
	// save image raster as grayscale .png from 0-65536 (2 images)
	short** gridA = grid_from_raster(widthA, heightA, rastered_trianglesA);
	short** gridB = grid_from_raster(widthB, heightB, rastered_trianglesB);
	save_raster("../../data_store/raster/rasterA.bin", gridA, widthA, heightA);
	save_raster("../../data_store/raster/rasterB.bin", gridB, widthB, heightB);

	vector<Mat> affine_forward = get_affine_transforms_forward(trianglesA, trianglesB);
	vector<Mat> affine_reverse = get_affine_transforms_reverse(trianglesB, trianglesA, affine_forward);

	float* affine_params = convert_vector_params(affine_forward, affine_reverse);
	write_float_array("../../data_store/affine/affine_1.bin", affine_params, trianglesA.size() * 12);

	cout << "Finished.";

	cin.get();
}

void trial_binary_render(uchar *image, int length, int width, int height) {
	Mat img(height, width, CV_8UC3, Scalar(0, 0, 0));
	for (int i = 0; i < height; i++) {
		for (int j = 0; j < width; j++) {

			int index = (i * width + j) * 3;

			uchar r = image[index];
			uchar g = image[index + 1];
			uchar b = image[index + 2];

			Vec3b color = Vec3b(r, g, b);

			img.at<Vec3b>(i, j) = color;
		}
	}
	Mat test2 = imread("../../data_store/images/david_2.jpg");
	cout << "test";
}

void fill_top_and_bottom(Mat &img) {
	Size img_size = img.size();
	int img_width = img_size.width;
	int img_height = img_size.height;

	int midpoint = img_height / 2;

	for (int j = 0; j < img_width; j++) {
		for (int i_top = midpoint; i_top > 0; i_top--) {
			Vec3b latest = img.at<Vec3b>(i_top + 1, j);
			Vec3b current = img.at<Vec3b>(i_top, j);
			int r = current[0];
			int g = current[1];
			int b = current[2];
			if (r == 0 && g == 0 && b == 0) {
				img.at<Vec3b>(i_top, j) = latest;
			}
		}

		for (int i_bottom = midpoint; i_bottom < img_height; i_bottom++) {
			Vec3b latest = img.at<Vec3b>(i_bottom - 1, j);
			Vec3b current = img.at<Vec3b>(i_bottom, j);
			int r = current[0];
			int g = current[1];
			int b = current[2];
			if (r == 0 && g == 0 && b == 0) {
				img.at<Vec3b>(i_bottom, j) = latest;
			}
		}
	}
}

void merge_and_save(string src_path_1, string src_path_2, string dst_path) {
	Mat img_1 = imread(src_path_1, IMREAD_COLOR);
	Mat img_2 = imread(src_path_2, IMREAD_COLOR);

	// Assumptions: img_1 and img_2 are of the same size
	// The images for the video capture are the same size as img_1 and img_2
	Mat merge = merge_images(img_1, img_2);

	// checking assumptions
	Size img_size_1 = img_1.size();
	Size img_size_2 = img_2.size();
	
	if (img_size_1.width != img_size_2.width || img_size_1.height != img_size_2.height) {
		throw "Irreconcilable sizes";
	}
	Size merge_size = merge.size();
	
	Mat new_img(img_size_1.height, merge_size.width, CV_8UC3);

	int height_diff = img_size_1.height - merge_size.height;
	if (height_diff < 0) {
		throw "Not implemented";
	}

	int top_diff = 0;
	int bottom_diff = 0;
	if (height_diff % 2 != 0) {
		top_diff = height_diff / 2 + 1;
		bottom_diff = height_diff / 2;
	}
	else {
		top_diff = height_diff / 2;
		bottom_diff = height_diff / 2;
	}

	// not sure if this is working quite as I intended it
	int original_i = 0;
	for (int i = top_diff; i < merge_size.height; i++) {
		for (int j = 0; j < merge_size.width; j++) {
			new_img.at<Vec3b>(i, j) = merge.at<Vec3b>(original_i, j);
		}
		original_i++;
	}

	// fill in middle with merge (black on top and bottom)
	fill_top_and_bottom(new_img);
	save_img(dst_path, new_img);

	cout << "done";
}

int danny_test() {
	// MAIN CALCULATIONS
	/*
	// master function for constructing and saving a frame
	
	string src_path_1 = "../../data_store/images/david_1.jpg";
	string tar_path_1 = "../../data_store/binary/david_1.bin";
	string src_path_2 = "../../data_store/images/david_2.jpg";
	string tar_path_2 = "../../data_store/binary/david_2.bin";

	save_img_binary(src_path_1, tar_path_1, src_path_2, tar_path_2);

	//string img1_path = "david_1.jpg";
	//string img2_path = "david_2.jpg";
	save_frame_master(src_path_1, src_path_2);
	*/

	// BACKGROUND MERGING
	/*
	string src_path_1 = "../../data_store/images/img_background_1.jpg";
	string src_path_2 = "../../data_store/images/img_background_2.jpg";
	string dst_path = "../../data_store/binary/background.bin";
	merge_and_save(src_path_1, src_path_2, dst_path);
	*/

	// FLASH DETECTION
	cout << "Test flash: " << test_flash() << endl;
	return 0;
}

int adrian_test() {
	//vector<Point2f> corners;
	//trackbarCorners("..\\data_store\\david_1.jpg", corners);
	//test_match_points("david_1.jpg", "david_2.jpg");

	//test_match_points_2("david_1.jpg", "david_2.jpg");
	//test_GFTT("david_1.jpg", "david_2.jpg");
	//test_AGAST("david_1.jpg", "david_2.jpg");
	//test_BRISK("david_1.jpg", "david_2.jpg");
	//test_FAST("david_1.jpg", "david_2.jpg");
	//test_ORB("david_1.jpg", "david_2.jpg");
	//test_affine_ORB("david_1.jpg", "david_2.jpg");

	//test_kmeans("david_1.jpg", "david_2.jpg");
	//vector<KeyPoint> bs1;
	//vector<KeyPoint> bs2;
	//affine_akaze_test("..\\data_store\\david_1.jpg", "..\\data_store\\david_2.jpg", bs1, bs2);
	//test_nbh_first("david_1.jpg", "david_2.jpg");
	//test_nbh_grow("david_1.jpg", "david_2.jpg");
	//test_one_nbh("david_1.jpg", "david_2.jpg");
	//test_akaze_harris_global_harris_local("david_1.jpg", "david_2.jpg");

	//loading an david seems to take approx 50ms, so two davids 100ms
	/*
	string address1 = "..\\data_store\\david_1.jpg";
	Mat img1 = imread(address1, IMREAD_GRAYSCALE);
	string address2 = "..\\data_store\\david_2_resize_no_background.jpg";
	Mat img2 = imread(address2, IMREAD_GRAYSCALE);
	chrono::high_resolution_clock::time_point t1 = chrono::high_resolution_clock::now();


	chrono::high_resolution_clock::time_point t2 = chrono::high_resolution_clock::now();
	chrono::duration<double, std::milli> time_span = t2 - t1;
	std::cout << "It took me " << time_span.count() / 10 << " milliseconds." << endl;
	return 0;
	*/
	/*
	string src_path_1 = "../../data_store/images/david_1.jpg";
	string tar_path_1 = "../../data_store/binary/david_1.bin";
	string src_path_2 = "../../data_store/images/david_2.jpg";
	string tar_path_2 = "../../data_store/binary/david_2.bin";

	save_img_binary(src_path_1, tar_path_1, src_path_2, tar_path_2);

	string img1_path = "david_1.jpg";
	string img2_path = "david_2.jpg";
	save_frame_master(img1_path, img2_path);
	*/
	test_bs();
	return 0;
}

int main()
{
	cout << APPLICATION_NAME << " version " << VERSION << endl;
	cout << COMPANY_NAME << " " << COPYRIGHT_YEAR << ". " << "All rights reserved." << endl;

	ifstream file("user_debug.txt");
	string str;
	getline(file, str);

	// Horrible hackish way of avoiding merge conflicts while we do testing

	if (str == "danny") {
		danny_test();
	}
	else if (str == "adrian") {
		adrian_test();	
	}
	else {
		cout << "Invalid user";
	}


	cout << "Finished. Press enter twice to terminate program.";

	cin.get();

    return 0;
} 