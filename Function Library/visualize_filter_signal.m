clear
%close all

%These are the pulse addresses you need to identify that you want to
%change
scanAddresses = [(3:2:67)+1,(75:2:139)+2];
npulses_to_scan = length(scanAddresses);


%random signal phase
deltas =  linspace(0,2*pi,100);
d_delta = deltas(2)-deltas(1);

% taustart = 300;
% tauend = 600;
npoints = 51;
pipulseduration = 32;

nu0filterstart = 0.8e6;%1/(2*taustart*1e-9);
nu0filterend = 1.8e6;%1/(2*tauend*1e-9);
nu0filter_vec = linspace(nu0filterstart,nu0filterend,npoints);
qfilter = 2*(1)/(9.6e-6);
t = linspace(0,20e-6,10000);
sweepduration = 9.6e-6;

% background = 10*linspace(0.2,1,length(nu0filter_vec));

nuhalfdeviation_filter = 250e3;
qsignal = 2*(nuhalfdeviation_filter)/sweepduration;
nu0signal = 1.15e6 - nuhalfdeviation_filter;
signal_c = cos(2*pi*t.*(nu0signal + qsignal*t)).*(t<=sweepduration);
signal_s = sin(2*pi*t.*(nu0signal + qsignal*t)).*(t<=sweepduration);

recovered_signal = zeros(1,npoints);

%What values you want the pulses above to take
%The first values are for the first pulse address, the second for the
%second address
scanValues = cell(1,npulses_to_scan);
for ii = 1:npulses_to_scan
    
    currpulseno = mod(ii,33);
    
    if currpulseno==1
        scanValues{ii} = round(nu0filter_vec/2/qfilter.*(sqrt(1 + qfilter./nu0filter_vec.^2)-1)*1e9 - 3/4*pipulseduration);
    elseif (currpulseno>=2)&&(currpulseno<=32)
        scanValues{ii} = round(nu0filter_vec/2/qfilter.*(sqrt(1 + 2*qfilter*(currpulseno-1/2)./nu0filter_vec.^2)-...
            sqrt(1 + 2*qfilter*(currpulseno-3/2)./nu0filter_vec.^2))*1e9 - pipulseduration);
    else
        scanValues{ii} = round(nu0filter_vec/2/qfilter.*(sqrt(1 + 2*qfilter*(32)./nu0filter_vec.^2)-...
            sqrt(1 + 2*qfilter*(32-1/2)./nu0filter_vec.^2))*1e9 - 3/4*pipulseduration);
    end

end

for aa = 1:npoints
    
    nu0 = nu0filter_vec(aa);

    filter = sign(cos(2*pi*t.*(qfilter*t + nu0)));
    
    pulsediagram = zeros(size(t));
    pulsediagram(t<=pipulseduration/4*1e-9) = 1;
    tpulse = 0;
    for bb = 1:npulses_to_scan/2
        if bb==1
            tpulse = tpulse + pipulseduration/4;
        else
            tpulse = tpulse + pipulseduration/2;
        end
        
        if bb<npulses_to_scan/2
            tpulse = tpulse + scanValues{bb}(aa) + pipulseduration/2;
        else
            tpulse = tpulse + scanValues{bb}(aa) + pipulseduration/4;
        end
        pulsediagram( abs(t-tpulse*1e-9)<= (pipulseduration/2*1e-9) ) = 1;
        
    end
    filter = filter.*(t<=tpulse*1e-9);
    
%     recovered_signal(aa) = sum(filter.*signal_c).^2 + sum(filter.*signal_s).^2;
    
    for delta = deltas
        recovered_signal(aa) = d_delta/2*cos((0.5e-3)*(cos(delta)*sum(filter.*signal_c)-sin(delta)*sum(filter.*signal_s))) + recovered_signal(aa);
    end
    recovered_signal(aa) = recovered_signal(aa)/2/pi;
%     plot(t,signal)
%     hold on
%     plot(t,pulsediagram)
%     plot(t,filter)
%     xlim([0 t(end)])
%     ylim([-1.25 1.25])
%     set(gcf,'position',[681   300   560   420])
end

figure
plot(nu0filter_vec,recovered_signal)
set(gcf,'position',[681   300   560   420])
ylim([0.25 0.6])