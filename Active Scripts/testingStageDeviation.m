% s = directMove(s,'y',99.34,'fine');
% s = directMove(s,'x',101.535,'fine');

s = stage('PI_stage');
s = connect(s);

[s,xLocationDeviance] = findLocationDeviance(s,'x',500);
xLocationDeviance = xLocationDeviance * 1e3;
xMean = mean(xLocationDeviance);
xStdDev = std(xLocationDeviance);
% [s,yLocationDeviance] = findLocationDeviance(s,'y',250);
% yLocationDeviance = yLocationDeviance * 1e3;
% yMean = mean(yLocationDeviance);
% yStdDev = std(yLocationDeviance);
% [s,zLocationDeviance] = findLocationDeviance(s,'z',250);
% zLocationDeviance = zLocationDeviance * 1e3;
% zMean = mean(zLocationDeviance);
% zStdDev = std(zLocationDeviance);


% sortedX = sort(xLocationDeviance,2,'descend');
figure (1)
plot(xLocationDeviance)
title('Deviation over time')
xlabel('number of asks')
ylabel('deviation from target (nm)')

discretizedData = discretize(xLocationDeviance,15);
for ii = 1:15
    nDataPoints(ii) = sum(discretizedData == ii);
end
minVal = min(xLocationDeviance);
maxVal = max(xLocationDeviance);
steps = minVal:(maxVal-minVal)/15:maxVal;

figure (2)
bar(steps(1:end-1),nDataPoints)
title('Deviation Probability Curve')
ylabel('Number of times per bin')
xlabel('Bin minimum value (nm)')