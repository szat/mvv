
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <string>
#include <stdio.h>
#include <iostream>

#include "binary_write.h"
#include "global_config.h"
#include "interpolate_images.h"
#include "polygon_raster.h"
#include "build_geometry.h"

#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/core/utility.hpp>

#include <opencv2/video.hpp>
//#include <opencv2/optflow.hpp>

//#include <opencv2/features2d/features2d.hpp>
#include <AKAZE.h>
#include <AKAZEConfig.h>
//#include <cuda_profiler_api.h>
#include <opencv2/calib3d.hpp> //AKAZE seems not to work without this

#define VERSION "1.0.6"
#define APPLICATION_NAME "MVV"
#define COPYRIGHT_AUTHORS "Adrian Szatmari, Daniel Hogg"
#define COPYRIGHT_YEAR 2017

using namespace std;
using namespace cv;
using namespace libAKAZECU;

const float MIN_H_ERROR = 5.00f;            ///< Maximum error in pixels to accept an inlier
const float DRATIO = 0.80f;

struct GeometricSlice {
	Rect img;
	vector<Vec6f> triangles;
};

struct MatchedGeometry {
	GeometricSlice source_geometry;
	GeometricSlice target_geometry;
};

string pad_frame_number(int frame_number) {
	// zero-padding frame number
	stringstream stream;
	stream << frame_number;
	string padded;
	stream >> padded;
	int str_length = padded.length();
	for (int i = 0; i < 6 - str_length; i++)
		padded = "0" + padded;
	return padded;
}

MatchedGeometry create_matched_geometry(std::vector<cv::Point2f> imgA_points, std::vector<cv::Point2f> imgB_points, cv::Size size) {
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

void ratio_matcher_script(const float ratio, const vector<KeyPoint>& kpts1_in, const vector<KeyPoint>& kpts2_in, const Mat& desc1_in, const Mat& desc2_in, vector<KeyPoint>& kpts1_out, vector<KeyPoint>& kpts2_out) {
	time_t tstart, tend;
	vector<vector<DMatch>> matchesLoweRatio;
	BFMatcher matcher(NORM_HAMMING);
	tstart = time(0);
	matcher.knnMatch(desc1_in, desc2_in, matchesLoweRatio, 2);
	int nbMatches = matchesLoweRatio.size();
	for (int i = 0; i < nbMatches; i++) {
		DMatch first = matchesLoweRatio[i][0];
		float dist1 = matchesLoweRatio[i][0].distance;
		float dist2 = matchesLoweRatio[i][1].distance;
		if (dist1 < ratio * dist2) {
			kpts1_out.push_back(kpts1_in[first.queryIdx]);
			kpts2_out.push_back(kpts2_in[first.trainIdx]);
		}
	}
	tend = time(0);
	cout << "Ratio matching with BF(NORM_HAMMING) and ratio " << ratio << " finished in " << difftime(tend, tstart) << "s and matched " << kpts1_out.size() << " features." << endl;
}

void ransac_script(const float ball_radius, const float inlier_thresh, const vector<KeyPoint>& kpts1_in, const vector<KeyPoint>& kpts2_in, Mat& homography_out, vector<KeyPoint>& kpts1_out, vector<KeyPoint>& kpts2_out) {
	cout << "RANSAC to estimate global homography with max deviating distance being " << ball_radius << "." << endl;

	vector<Point2f> keysImage1;
	vector<Point2f> keysImage2;
	vector<DMatch> good_matches;

	int nbMatches = kpts1_in.size();
	for (int i = 0; i < nbMatches; i++) {
		keysImage1.push_back(kpts1_in.at(i).pt);
		keysImage2.push_back(kpts2_in.at(i).pt);
	}

	Mat H = findHomography(keysImage1, keysImage2, CV_RANSAC, ball_radius);
	homography_out = H;

	cout << "RANSAC found the homography." << endl;

	nbMatches = kpts1_in.size();
	for (int i = 0; i < nbMatches; i++) {
		Mat col = Mat::ones(3, 1, CV_64F);// , CV_32F);
		col.at<double>(0) = kpts1_in[i].pt.x;
		col.at<double>(1) = kpts1_in[i].pt.y;

		col = H * col;
		col /= col.at<double>(2); //because you are in projective space
		double dist = sqrt(pow(col.at<double>(0) - kpts2_in[i].pt.x, 2) + pow(col.at<double>(1) - kpts2_in[i].pt.y, 2));

		if (dist < inlier_thresh) {
			int new_i = static_cast<int>(kpts1_out.size());
			kpts1_out.push_back(kpts1_in[i]);
			kpts2_out.push_back(kpts2_in[i]);
		}
	}

	cout << "Homography filtering with inlier threshhold of " << inlier_thresh << " has matched " << kpts1_out.size() << " features." << endl;
}

void akaze_script(float akaze_thresh, const Mat& img_in, vector<KeyPoint>& kpts_out, Mat& desc_out) {
	time_t tstart, tend;
	tstart = time(0);

	
	AKAZEOptions options;
	/*
	Mat img_gray;
	cvtColor(img_in, img_gray, CV_BGR2GRAY);
	*/
	Mat img_32;
	img_in.convertTo(img_32, CV_32F, 1.0 / 255.0, 0);

	// Don't forget to specify image dimensions in AKAZE's options
	options.img_width = img_in.cols;
	options.img_height = img_in.rows;

	// Extract features
	libAKAZECU::AKAZE evolution(options);

	evolution.Create_Nonlinear_Scale_Space(img_32);
	evolution.Feature_Detection(kpts_out);
	evolution.Compute_Descriptors(kpts_out, desc_out);

	tend = time(0);
	cout << "akaze_wrapper(thr=" << akaze_thresh << ",[h=" << img_in.size().height << ",w=" << img_in.size().width << "]) finished in " << difftime(tend, tstart) << "s and found " << kpts_out.size() << " features." << endl;
}

vector<vector<KeyPoint>> match_points_mat(Mat img1, Mat img2)
{
	const float akaze_thr = 3e-4;    // AKAZE detection threshold set to locate about 1000 keypoints
	const float ratio = 0.8f;   // Nearest neighbor matching ratio
	const float inlier_thr = 20.0f; // Distance threshold to identify inliers
	const float ball_radius = 5;

	vector<KeyPoint> kpts1_step1;
	vector<KeyPoint> kpts2_step1;
	Mat desc1_step1;
	Mat desc2_step1;

	akaze_script(akaze_thr, img1, kpts1_step1, desc1_step1);
	akaze_script(akaze_thr, img2, kpts2_step1, desc2_step1);

	vector<KeyPoint> kpts1_step2;
	vector<KeyPoint> kpts2_step2;
	ratio_matcher_script(ratio, kpts1_step1, kpts2_step1, desc1_step1, desc2_step1, kpts1_step2, kpts2_step2);

	Mat homography;
	vector<KeyPoint> kpts1_step3;
	vector<KeyPoint> kpts2_step3;
	ransac_script(ball_radius, inlier_thr, kpts1_step2, kpts2_step2, homography, kpts1_step3, kpts2_step3);

	vector<vector<KeyPoint>> pointMatches = { kpts1_step3, kpts2_step3 };
	return pointMatches;
}

MatchedGeometry read_matched_points_from_file(Mat &img1, Mat &img2, Size video_size) {
	cout << "Initializing matched geometry routine" << endl;

	Mat imgA;
	Mat imgB;
	cvtColor(img1, imgA, CV_BGR2GRAY);
	cvtColor(img2, imgB, CV_BGR2GRAY);

	vector<vector<KeyPoint>> point_matches = match_points_mat(imgA, imgB);

	vector<KeyPoint> imgA_keypoints = point_matches[0];
	vector<KeyPoint> imgB_keypoints = point_matches[1];
	vector<Point2f> imgA_points = convert_key_points(imgA_keypoints);
	vector<Point2f> imgB_points = convert_key_points(imgB_keypoints);

	MatchedGeometry geometry = create_matched_geometry(imgA_points, imgB_points, video_size);
	return geometry;
}

void save_frame_master(Mat &img1, Mat &img2, Size video_size, string affine, string rasterA, string rasterB) {
	MatchedGeometry geometry = read_matched_points_from_file(img1, img2, video_size);

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
	save_raster(rasterA, gridA, widthA, heightA);
	save_raster(rasterB, gridB, widthB, heightB);

	vector<Mat> affine_forward = get_affine_transforms_forward(trianglesA, trianglesB);
	vector<Mat> affine_reverse = get_affine_transforms_reverse(trianglesB, trianglesA, affine_forward);

	float* affine_params = convert_vector_params(affine_forward, affine_reverse);
	write_float_array(affine, affine_params, trianglesA.size() * 12);
	free(affine_params);
}

int video_loop(VideoCapture & cap_1, VideoCapture & cap_2, int start_1, int start_2) {

	// do the point matching at max resolution, then rescale
	// doens't seem like we do any rescaling

	int starter_offset = 10;

	start_1 = start_1 + starter_offset;
	start_2 = start_2 + starter_offset;

	int num_frames_1 = cap_1.get(CV_CAP_PROP_FRAME_COUNT);
	int num_frames_2 = cap_2.get(CV_CAP_PROP_FRAME_COUNT);

	int width_1 = cap_1.get(CV_CAP_PROP_FRAME_WIDTH);
	int height_1 = cap_1.get(CV_CAP_PROP_FRAME_HEIGHT);

	int width_2 = cap_2.get(CV_CAP_PROP_FRAME_WIDTH);
	int height_2 = cap_2.get(CV_CAP_PROP_FRAME_HEIGHT);

	if (width_1 != width_2 || height_1 != height_2) {
		cout << "ERROR CODE 004: The widths and heights of both video files must be the same. We recommend shooting footage with two identical cameras." << endl;
		return -1;
	}

	Size video_size = Size(width_1, height_1);

	cap_1.set(CV_CAP_PROP_POS_FRAMES, start_1);
	cap_2.set(CV_CAP_PROP_POS_FRAMES, start_2);

	Mat next_1;
	Mat next_2;

	int frames_remaining_1 = num_frames_1 - start_1 - 1;
	int frames_remaining_2 = num_frames_2 - start_2 - 1;
	int frames_remaining = min(frames_remaining_1, frames_remaining_2);

	// Determining how many 'jumps' are required.
	// TODO: Replace these variables with more descriptive and intuitive names.

	int renderable_frames = frames_remaining - frames_remaining % 20;
	int jump_size = 20;
	int num_jumps = renderable_frames / 20;
	int cutoff_frame = jump_size * num_jumps;

	for (int i = 0; i <= cutoff_frame; i += jump_size) {
		string padded_number = pad_frame_number(i);
		cout << "Processing frame " << i << " of " << cutoff_frame << endl;

		string affine_dir = "../../data_store/affine/";
		string filename_affine = "affine_" + padded_number + ".bin";

		string raster_dir = "../../data_store/raster/";
		string filename_raster_1 = "raster_1_" + padded_number + ".bin";
		string filename_raster_2 = "raster_2_" + padded_number + ".bin";

		string image_dir = "../../data_store/binary/";
		string filename_img_1 = "img1_" + padded_number + ".bin";
		string filename_img_2 = "img2_" + padded_number + ".bin";

		string affine = affine_dir + filename_affine;
		string raster1 = raster_dir + filename_raster_1;
		string raster2 = raster_dir + filename_raster_2;
		string img1;
		string img2;

		cap_1.read(next_1);
		cap_2.read(next_2);

		save_frame_master(next_1, next_2, video_size, affine, raster1, raster2);

		cout << "Saving image for frame " << i << endl;
		padded_number = pad_frame_number(i);
		filename_img_1 = "img1_" + padded_number + ".bin";
		filename_img_2 = "img2_" + padded_number + ".bin";
		img1 = image_dir + filename_img_1;
		img2 = image_dir + filename_img_2;
		save_img_binary(next_1, next_2, video_size, img1, img2);

		for (int j = 1; j < 20; j++) {
			cout << "Saving image for frame " << (i + j) << endl;
			cap_1.read(next_1);
			cap_2.read(next_2);
			padded_number = pad_frame_number(i + j);
			filename_img_1 = "img1_" + padded_number + ".bin";
			filename_img_2 = "img2_" + padded_number + ".bin";
			img1 = image_dir + filename_img_1;
			img2 = image_dir + filename_img_2;
			save_img_binary(next_1, next_2, video_size, img1, img2);
		}
	}
	return -1;
}

pair<int, int> audio_sync(int initial_offset, float delay, int framerate) {
	//6.2657
	//95
	std::pair<int, int> sync = std::pair<int, int>(initial_offset, initial_offset);
	float offset2 = delay * (float)framerate;
	int offset2_int = (int)offset2;
	sync.first = initial_offset;
	sync.second = initial_offset + offset2_int;
	return sync;
}

int main() {
	// Initializing application
	cout << APPLICATION_NAME << " version " << VERSION << endl;
	cout << COPYRIGHT_AUTHORS << " " << COPYRIGHT_YEAR << ". " << "MIT License." << endl;

	// Getting input parameters from the configuration file settings.ini.

	string video_path_1 = get_video_path_1();
	string video_path_2 = get_video_path_2();

	int framerate = get_framerate();
	if (framerate <= 0) {
		cout << "ERROR CODE 003: Framerate must be a positive integer." << endl;
		return -1;
	}

	int start_offset = get_start_offset();
	if (framerate <= 0) {
		cout << "ERROR CODE 005: Starting offset cannot be less than 0 (cannot start before the beginning of the video file)." << endl;
		return -1;
	}

	float delay = get_delay();

	VideoCapture cap_1(video_path_1);
	if (!cap_1.isOpened()) {
		cout << "ERROR CODE 002: Video file not found. Please verify the file specified exists in the folder: data_store/video." << endl;
		return -1;
	}

	VideoCapture cap_2(video_path_2);
	if (!cap_2.isOpened()) {
		cout << "ERROR CODE 002: Video file not found. Please verify the file specified exists in the folder: data_store/video." << endl;
		return -1;
	}

	std::pair<int, int> initial_offset = audio_sync(start_offset, delay, framerate);
	video_loop(cap_1, cap_2, initial_offset.first, initial_offset.second);

	cout << "Finished processing video files. Press enter to terminate program." << endl;
	cin.get();

	return 0;
}