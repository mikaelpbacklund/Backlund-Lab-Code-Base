% clear
% close all
% load("Overnight_Correlation_1-6us_20ns_stepSize_python_comparison.mat")

for ii = 1:size(data.values,1)
   for jj = 1:size(data.values,2)
      r1(jj) = data.values{ii,jj}(1); %#ok<*SAGROW>
      s1(jj) = data.values{ii,jj}(2);
      c1(jj) = (r1(jj)-s1(jj))/r1(jj);
   end
   r(ii) = mean(r1);
   s(ii) = mean(s1);
   averagingOverContrast(ii) = mean(c1);
   contrastFromAverageSR(ii) = (r(ii)-s(ii))/r(ii);
end

%%
nScan = 1;
xax = scanInfo.bounds{nScan}(1):scanInfo.stepSize(nScan):scanInfo.bounds{nScan}(2);

%%
% f{1} = figure(1);
% a{1} = axes(f{1});
% p{1} = plot(a{1},xax,r);
% title('Reference')
% xlabel('t (ns)')
% ylabel('Voltage (V)')

% f{2} = figure(2);
% a{2} = axes(f{2});
% p{2} = plot(a{2},xax,s);
% title('Signal')
% xlabel('t (ns)')
% ylabel('Voltage (V)')

f{3} = figure(3);
a{3} = axes(f{3});
p{3} = plot(a{3},xax,averagingOverContrast);
title('Contrast (Average of Each Contrast Value)')
xlabel('t (ns)')
ylabel('Contrast')

f{4} = figure(4);
a{4} = axes(f{4});
p{4} = plot(a{4},xax,contrastFromAverageSR);
title('Contrast (Contrast of Average Signal and Reference)')
xlabel('t (ns)')
ylabel('Contrast')