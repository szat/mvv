#include "opencv2/imgcodecs.hpp"
#include "opencv2/imgproc.hpp"
#include "opencv2/videoio.hpp"
#include <opencv2/highgui.hpp>
#include <opencv2/video.hpp>
//C
#include <stdio.h>
//C++
#include <iostream>
#include <sstream>

using namespace cv;
using namespace std;

#include "background_substraction.h"

int test_bs() {
	Mat frame; //current frame
	Mat fgMaskMOG2; //fg mask fg mask generated by MOG2 method
	Ptr<BackgroundSubtractor> pMOG2; //MOG2 Background subtractor
	int keyboard = 0; //input from keyboard
	cout << "We are in test_bs()" << endl;

	namedWindow("Frame");
	namedWindow("FG Mask");
	pMOG2 = createBackgroundSubtractorMOG2(); //MOG2 approach

	//Open Video File
	string first_frame_path = "C:/Users/Adrian/Documents/saisiecol1/cam-000/img_000000.png"; 
	//read the first file of the sequenc
	frame = imread(first_frame_path);
	if (frame.empty()) {
		//error in opening the first image
		cerr << "Unable to open first image frame: " << first_frame_path << endl;
		exit(EXIT_FAILURE);
	}
	//current image filename
	//string fn(first_frame_path);
	//read input data. ESC or 'q' for quitting

	int counter = 0;
	while ((char)keyboard != 'q' && (char)keyboard != 27) {
		//string next_frame_path = prefix + nextFrameNumberString + suffix;
		string frame_number_string = to_string(counter);
		string next_frame_path = "C:/Users/Adrian/Documents/saisiecol1/cam-000/img_000000";
		int length = frame_number_string.length();
		for (int i = 0; i < length; ++i) {
			next_frame_path.pop_back();
		}
		next_frame_path += frame_number_string;
		next_frame_path += ".png";
		cout << next_frame_path << endl;
		counter++;
		
		cout << "counter is " << counter << endl;
		frame = imread(next_frame_path);
		if (frame.empty()) {
			//error in opening the next image in the sequence
			cerr << "Unable to open image frame: " << next_frame_path << endl;
			exit(EXIT_FAILURE);
		}

		pMOG2->apply(frame, fgMaskMOG2);

		imshow("Frame", frame);
		imshow("FG Mask MOG 2", fgMaskMOG2);

		keyboard = waitKey(30);
	}
	
	return 0;
}