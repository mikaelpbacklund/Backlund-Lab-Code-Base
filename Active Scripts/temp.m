% clear s r c meanS meanR totalC cumulativeC nMR nMC nMS nShotC finalDifferenceShot finalDifferenceMean
% unData = ex.DAQ.handshake.UserData.unsortedData;

nPointsPerLoop = 6;
locationNumbers = 1:1000;

nRemoved = zeros(1,numel(locationNumbers));
for kk = 1:numel(locationNumbers)

currentData = double(unData{locationNumbers(kk)})./1000;

dataOn = currentData(:,3) == 1;
signalOn = currentData(:,4) == 1;

rLocations = find(dataOn & ~signalOn);
sLocations = find(dataOn & signalOn);

tradRMean(kk) = mean(currentData(rLocations,2)); %#ok<*SAGROW>
tradSMean(kk) = mean(currentData(sLocations,2));
tradC(kk) = (tradRMean(kk) - tradSMean(kk))./tradRMean(kk);

for ii = 1:2
    if ii == 1
        locations = find(dataOn & ~signalOn);        
    else
        locations = find(dataOn & signalOn);
    end
    loopCutoffs = find(diff(locations)~=1);
    cutoffDiff = diff(loopCutoffs);
    notExpectedPoints = find(cutoffDiff ~= mode(cutoffDiff));
    locationToCut = loopCutoffs(notExpectedPoints)+1;
    locations(locationToCut) = [];
    nRemoved(kk) = nRemoved(kk) + numel(locationToCut);
    if ii == 1
        meanR(kk) = mean(currentData(locations,2));
    else
        meanS(kk) = mean(currentData(locations,2));
    end    
end
meanC(kk) = (meanR(kk) - meanS(kk))./meanR(kk);

% for ii = 1:floor(numel(dataOn/nSamplesPerLoop))
%     if ii+nSamplesPerLoop-1 > numel(dataOn)
%         break
%     end
%     for jj = 1:nSamplesPerLoop/2
%         firstData(jj) = currentData(dataOn(ii+jj-1),2); %#ok<*SAGROW>
%         secondData(jj) = currentData(dataOn(ii+jj-1+nSamplesPerLoop/2),2);
%     end
%     firstData = mean(firstData);
%     secondData = mean(secondData);
% 
%     if currentData(dataOn(ii),4)
%         s(ii) = firstData;
%         r(ii) = secondData;
%     else
%         r(ii) = firstData;
%         s(ii) = secondData;
%     end
% 
%     c(ii) = (r(ii)-s(ii))/r(ii);
% end

% dataOn = currentData(:,3) > 0;
% signalOn = currentData(:,4)>0;
% meanS(kk) = mean(currentData(dataOn & signalOn,2));
% meanR(kk) = mean(currentData(dataOn & ~signalOn,2));
% 
% totalC(kk) = (meanR(kk)-meanS(kk))/meanR(kk);
% cumulativeC(kk) = mean(c);
%  if kk == 1
%      storedC = c;
%  end


%%
% [rTransform,~] = fourierTransform(r,1);
% [sTransform,~] = fourierTransform(s,1);
% [cTransform,~] = fourierTransform(c,1);
% normalR = rTransform(rTransform<.002);
% invR = ifft(normalR);
% figure (1)
% plot(abs(invR))
% normalC = cTransform(cTransform<.002);
% invC = ifft(normalC);
% figure (2)
% plot(abs(invC))

% data = r;
% 
% fData = fft(data);
% figure (1)
% title('Fourier of original data')
% realData = abs(fData(2:end));
% plot(realData)
% fData(realData > 2.5)=  0;
% 
% test = ifft(fData);
% figure (2)
% plot(abs(test))

%%

% adjustedR = adjustData(r);
% figure (1)
% 
% plot(adjustedR)
% title('R')

% adjustedS = adjustData(s);
% figure (2)
% 
% plot(adjustedS)
% title('S')

% adjustedC = adjustData(c);
% figure (3)
% 
% plot(adjustedC)
% title('C')

% newC = (adjustedR - adjustedS)./adjustedR;

% figure (4)
% 
% plot(newC)
% title('new C')

% nMR(kk) = mean(adjustedR);
% nMS(kk) = mean(adjustedS);
% nMC(kk) = (nMR-nMS)/nMR;
% nShotC(kk) = mean(newC);
% 
% finalDifferenceMean(kk) = totalC(kk)-nMC(kk);
% finalDifferenceShot(kk) = totalC(kk)-nShotC(kk);
end

%%

removedOutlierNew = meanC(meanC < 2e-3);
removedOutlierTrad = tradC(tradC < 2e-3);
figureOfMeritTrad = std(removedOutlierTrad);
figureOfMeritNew = std(removedOutlierNew);

%%
figure (1)
plot(removedOutlierTrad)
title('Regular contrast')

figure (2)
plot(removedOutlierNew)
title('Adjusted contrast')

figure (3)
plot(nRemoved)
title('Number of points removed')

% figure (3)
% plot(nMC)
% title('Adjusted Mean Contrast')
% 
% figure (4)
% plot(finalDifferenceMean)
% title('Difference between normal and adjusted')

%%
for ii = 1:ex.scan.nSteps
    rData(ii) = ex.data.values{ii}(1);
    sData(ii) = ex.data.values{ii}(2);
    cData(ii) = (rData(ii)-sData(ii))./rData(ii);
end

figure (5)
plot(cData)
title('From Actual Data')

function [adjustedSpectrum] = adjustData(dataToAdjust)
fData = fft(dataToAdjust);
realData = abs(fData);
fData(realData > mean(realData)+std(realData)*1)=  0;
adjustedSpectrum = abs(ifft(fData));
end
