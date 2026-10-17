function ex = plotAll(ex,p,currentLocation)
assignin("base","currentLocation",currentLocation)
%Create matrix where first row is ref, second is sig, and columns indicate iteration
data = createDataMatrixWithIterations(ex,currentLocation);
%Find average data across iterations by taking mean across all columns
averageData = mean(data,2);
%Current data is last column
currentData = data(:,end);
%Gets data points
dataPoints = ex.data.nPoints(currentLocation{:},:);

if isscalar(averageData)
    averageData(2) = 0;
end
if isscalar(currentData)
    currentData(2) = 0;
end
averageContrast = (averageData(1) - averageData(2)) / averageData(1);
currentContrast = (currentData(1) - currentData(2)) / currentData(1);

yAxisLabel = 'Contrast';
if p.plotAverageContrast
    ex = plotData(ex,averageContrast,'Average Contrast',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotCurrentContrast
    ex = plotData(ex,currentContrast,'Current Contrast',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if strcmpi(p.collectionType,'analog')
    yAxisLabel = 'Reference (V)';
elseif strcmpi(p.collectionType,'counter') && p.perSecond
    yAxisLabel = 'Reference (counts/s)';
else
    yAxisLabel = 'Reference (counts)';
end

if p.plotAverageReference
    ex = plotData(ex,averageData(1),'Average Reference',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotCurrentReference
    ex = plotData(ex,currentData(1),'Current Reference',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotAverageSignal
    ex = plotData(ex,averageData(2),'Average Signal',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotCurrentSignal
    ex = plotData(ex,currentData(2),'Current Signal',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end

yAxisLabel = 'SNR (arbitrary units)';
if p.plotAverageSNR
    if ~p.invertSignalForSNR
        SNRVal = sqrt(averageData(1)) * averageContrast;
    else
        SNRVal = sqrt(averageData(1)) * averageContrast^(-1);
    end
    SNRVal = abs(SNRVal) * sqrt(mean(dataPoints,"all"));
    ex = plotData(ex,SNRVal,'Average SNR',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotCurrentSNR
    if ~p.invertSignalForSNR
        SNRVal = sqrt(currentData(1)) * currentContrast;
    else
        SNRVal = sqrt(currentData(1)) * currentContrast^(-1);
    end
    SNRVal = abs(SNRVal) * sqrt(dataPoints(ex.data.iteration(currentLocation{:})));
    ex = plotData(ex,SNRVal,'Current SNR',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end

yAxisLabel = 'Number of Data Points';
if p.plotAverageDataPoints
    ex = plotData(ex,mean(dataPoints,"all"),'Average Data Points',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end
if p.plotCurrentDataPoints
    ex = plotData(ex,dataPoints(ex.data.iteration(currentLocation{:})),'Current Data Points',yAxisLabel,p.boundsToUse,[],currentLocation,p.xOffset);
end

%If a new post-optimization value is needed, record current data
if ex.optimizationInfo.enableOptimization && ex.optimizationInfo.needNewValue
    ex.optimizationInfo.postOptimizationValue = currentData(1);
    ex.optimizationInfo.needNewValue = false;
end

%Adds iteration to plot title if plotting periodically
if p.plotEveryNIterations > 1 && nDataPoint == 1
    fn = fieldnames(ex.plots);
    for jj = 1:numel(fn)
        if ~isgraphics(ex.plots.(fn{jj}).figure)
            continue
        end
        oldString = ex.plots.(fn{jj}).axes.Title.String;
        if ii == 1
            newString = strcat(oldString,sprintf(', Iteration %d',ii));
        else
            %Replaces the digits starting at the end of the string with
            %the current iteration
            newString = regexprep(oldString, '\d+$', num2str(ii));
        end
        ex.plots.(fn{jj}).axes.Title.String = newString;
    end
end
end