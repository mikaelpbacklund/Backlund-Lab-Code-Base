% clear
% close all
% load("Overnight_Correlation_1-6us_20ns_stepSize_python_comparison.mat")

data = savedData;
scanInfo = dataInfo{5,2};

startIt = [1,21,41,61,81];
endIt = [20,40,60,80,100];
plotRef = false;
plotSig = false;
plotAvgCon = true;
plotConOfAvg = false;
plotFFTCon = true;

extraTime = 550-392;

clear r s c

nPoints = size(data.values,1);
for itSet = 1:numel(startIt)
   nIts = 1+endIt(itSet)-startIt(itSet);
   r = zeros(nPoints,nIts);
   s = r;

   for ii = 1:nPoints
      for jj = 1:nIts
         r(ii,jj) = data.values{ii,jj+startIt(itSet)-1}(1);
         s(ii,jj) = data.values{ii,jj+startIt(itSet)-1}(2);
      end
   end

   c = (r-s)./r;

   avgC = mean(c,2);
   avgS = mean(s,2);
   avgR = mean(r,2);

   cFromAverageSR = (avgR-avgS)./avgR;
   if numel(startIt) > 1
      rSet{itSet} = r; %#ok<*SAGROW>
      sSet{itSet} = s;
      cSet{itSet} = c;
      avgCSet{itSet} = avgC;
   end
end

nScan = 2;
xax = scanInfo.bounds{nScan}(1)+extraTime:scanInfo.stepSize(nScan):scanInfo.bounds{nScan}(2)+extraTime;

%%

close all

dataType = 'Voltage (V)';
xaxType = 'τ (ns)';

if plotRef
f{1} = figure(1); %#ok<*UNRCH>
a{1} = axes(f{1});
p{1} = plot(a{1},xax,avgR);
title('Reference')
xlabel(xaxType)
ylabel(dataType)
end

if plotSig
f{2} = figure(2);
a{2} = axes(f{2});
p{2} = plot(a{2},xax,avgS);
title('Signal')
xlabel(xaxType)
ylabel(dataType)
end

if plotAvgCon
f{3} = figure(3);
a{3} = axes(f{3});
for ii = 1:numel(startIt)
   pSet{ii} = plot(a{3},xax,avgCSet{ii});
   hold on
   legendLabel{ii} = sprintf("Iteration %d-%d",startIt(ii),endIt(ii));
end
hold off
legend(legendLabel)
title('Contrast (Average of Each Contrast Value)')
xlabel(xaxType)
ylabel('Contrast')
end

if plotConOfAvg
f{4} = figure(4);
a{4} = axes(f{4});
p{4} = plot(a{4},xax,cFromAverageSR);
title('Contrast (Contrast of Average Signal and Reference)')
xlabel(xaxType)
ylabel('Contrast')
end

%%
% f{5} = figure(5);
% a{5} = axes(f{5});
% p{5} = plot(a{5},xax,avgC);
% title('Contrast (Iteration 1)')
% xlabel(xaxType)
% ylabel('Contrast')
% 
% f{6} = figure(6);
% a{6} = axes(f{6});
% p{6} = plot(a{6},xax,avgC);
% title('Cleaned Contrast (Iteration 1)')
% xlabel(xaxType)
% ylabel('Contrast')

% cCleaned = zeros(size(c));
% for jj = 1:nIts
%    iterationData = c(:,jj);
%    iterationData(isoutlier(iterationData)) = avgC(isoutlier(iterationData));
%    cCleaned(:,jj) = iterationData;
%    % p{1,5}.YData = iterationData;
%    % a{5}.Title.String = sprintf('Contrast (Iteration %d',jj);
%    % p{1,6}.YData = cCleaned(:,jj);
%    % a{6}.Title.String = sprintf('Cleaned Contrast (Iteration %d',jj);
%    % pause(.1)
% end

% %%
% avgCCleaned = mean(cCleaned,2);
% f{7} = figure(7);
% a{7} = axes(f{7});
% p{7} = plot(a{7},xax,avgCCleaned);
% title('Cleaned Contrast (Iteration 1)')
% xlabel(xaxType)
% ylabel('Contrast')

%%
magStrength = ResonanceDip(474,'magnet strength','1H');
frequencyStepSize = scanInfo.stepSize(1);%ns
frequencyAxis = (1:(scanInfo.nSteps-1)/2)/(frequencyStepSize*scanInfo.nSteps);
frequencyAxis = frequencyAxis/(magStrength*1e-4);%1e4 is gauss to tesla

% Perform FFT on all iterations at once
fftOut = abs(fftshift(fft(c - mean(c, 1), [], 1)));
% Single sided FFT
fftOut = fftOut(ceil((scanInfo.nSteps+1)/2)+1:end, :);
% Average across iterations
fftOut = mean(fftOut, 2);

if plotFFTCon
f{8} = figure(8);
a{8} = axes(f{8});
p{8} = plot(a{8},frequencyAxis,fftOut);
title('Fourier Transform of Contrast')
xlabel(xaxType)
ylabel('Intensity')
end

% % Perform FFT on all iterations at once
% fftOut = abs(fftshift(fft(cCleaned - mean(cCleaned, 1), [], 1)));
% % Single sided FFT
% fftOut = fftOut(ceil((scanInfo.nSteps+1)/2)+1:end, :);
% % Average across iterations
% fftOut = mean(fftOut, 2);

% f{9} = figure(9);
% a{9} = axes(f{9});
% p{9} = plot(a{9},frequencyAxis,fftOut);
% title('Fourier Transform of Contrast (Cleaned)')
% xlabel(xaxType)
% ylabel('Intensity')

%%
