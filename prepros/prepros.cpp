// prepros.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"
#include <string>
#include <stdio.h>
#include <iostream>

#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/core/utility.hpp>

#include <AKAZE.h>
#include <AKAZEConfig.h>

using namespace std;
using namespace cv;

int main()
{
	cv::Mat img1;
	std::string img1_path = "..\\data_store\\images\\c1_img_000177.png";
	img1 = cv::imread(img1_path);
	if (img1.empty())
	{
		std::cout << "Could not open image..." << img1_path << "\n";
		return -1;
	}

	AKAZEOptions options;
	libAKAZECU::AKAZE evolution1(options);

    return 0;
}