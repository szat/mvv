#pragma once

#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/opencv.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <vector>
#include <iostream>
#include <ctime>

bool has_suffix(const std::string &str, const std::string &suffix);

bool has_image_suffix(const std::string &str);

void akaze_wrapper(float akaze_thresh, const cv::Mat& img_in, std::vector<cv::KeyPoint>& kpts_out, cv::Mat& desc_out, bool verbose);

void ratio_matcher_wrapper(const float ratio, const std::vector<cv::KeyPoint>& kpts1_in, const std::vector<cv::KeyPoint>& kpts2_in, const cv::Mat& desc1_in, const cv::Mat& desc2_in, std::vector<cv::KeyPoint>& kpts1_out, std::vector<cv::KeyPoint>& kpts2_out, bool verbose);

void ransac_wrapper(const float ball_radius, const float inlier_thresh, const std::vector<cv::KeyPoint>& kpts1_in, const std::vector<cv::KeyPoint>& kpts2_in, cv::Mat& homography_out, std::vector<cv::KeyPoint>& kpts1_out, std::vector<cv::KeyPoint>& kpts2_out, bool verbose);

int test_match_points(void);