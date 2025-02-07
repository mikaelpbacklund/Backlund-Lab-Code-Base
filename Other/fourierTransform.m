function [outputSpectrum,frequencyAxis] = fourierTransform(data,stepSize)
%Variable argument is for vertical line location if desired

%Finds the sampling frequency from the step size(ns)
samplingRate = 1/stepSize;

%Number of datapoints taken
L = numel(data);

%Creates the xaxis of the fourier transformed plot
frequencyAxis = samplingRate*(0:(L/2))/L;

%Computes the fourier transform of the contrast data. P1 is the single
%sided spectrum (y axis of fourier transform) and P2 is the double sided
%spectrum (used only to calculate P1).
transformedData = abs(fft(data));
P2 = transformedData/L;
P1 = P2(1:floor(L/2+1));
P1(2:end-1) = 2*P1(2:end-1);

%Removes first point of the fourier transform graph, as the initial
%frequency may be 0
outputSpectrum = P1(2:end);
frequencyAxis = frequencyAxis(2:end);
end
