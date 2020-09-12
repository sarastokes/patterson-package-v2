classdef F1F2Figure < symphonyui.core.FigureHandler
% F1F2FIGURE
%
% Description:
%   Generic figure for F1 amplitude/phase and optional F2 amplitude.
%
% History:
%   25Apr2017 - SSP
%   20Feb2019 - SSP - Cleaned up for new rigs
% -------------------------------------------------------------------------
    
    properties (SetAccess = private)
        % Required
        device
        xvals
        onlineAnalysis
        preTime
        stimTime
        
        % Optional
        temporalFrequency   % Specify unless defined in epoch parameters
        xName               % X-axis name, as specified in epoch parameters
        waitTime            % Delay between stimTime and modulation onset
        titlestr            % Figure title
        axisType            % Linear or log (default = linear)
        showF2              % Show F2 amplitude? (default = true)
    end
    
    properties (Hidden = true, Access = private)
        axesHandle
        lineHandle
        repsPerX
        F1            
        F2           
        P1       
        epochNum
    end
    
    properties (Constant = true, Hidden = true)
        BINRATE = 60        % Hz
    end
    
    methods
        function obj = F1F2Figure(device, xvals, onlineAnalysis, preTime, stimTime, varargin)
            obj.device = device;
            obj.xvals = xvals;
            obj.onlineAnalysis = onlineAnalysis;
            obj.preTime = preTime;
            obj.stimTime = stimTime;
            
            ip = inputParser();
            ip.CaseSensitive = false;
            ip.addParameter('temporalFrequency', [], @(x)isvector(x));
            ip.addParameter('showF2', false, @(x)islogical(x));
            ip.addParameter('waitTime', 0, @(x)isnumeric(x));
            ip.addParameter('xName', [], @(x)ischar(x));
            ip.addParameter('titlestr', [], @(x)ischar(x));
            ip.addParameter('axisType', 'linear', @(x)ischar(x));
            ip.parse(varargin{:});
            
            obj.temporalFrequency = ip.Results.temporalFrequency;
            obj.waitTime = ip.Results.waitTime;
            obj.titlestr = ip.Results.titlestr;
            obj.axisType = ip.Results.axisType;
            obj.showF2 = ip.Results.showF2;
            obj.xName = ip.Results.xName;
            
            obj.F1 = zeros(size(obj.xvals));
            obj.F2 = zeros(size(obj.xvals));
            obj.P1 = zeros(size(obj.xvals));
            obj.repsPerX = zeros(size(obj.xvals));
            
            obj.epochNum = 0;
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            captureFigureButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Store Sweep',...
                'Separator', 'on',...
                'ClickedCallback', @obj.onSelectedCaptureFigure);
            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+icons\'];
            setIconImage(captureFigureButton, [iconDir, 'save_image.png']);
              
            obj.axesHandle(1) = subplot(3,1,1:2,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto',...
                'XScale', obj.axisType);
            
            obj.axesHandle(2) = subplot(3,1,3,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto');
            
            set(obj.figureHandle, 'Color', 'w');
            
            ylabel(obj.axesHandle(1), 'spikes/sec');
            xlabel(obj.axesHandle(2), obj.xName);
            ylabel(obj.axesHandle(2), 'phase');
            if ~isempty(obj.titlestr)
                obj.setTitle(obj.titlestr);
            end
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle(1), t);
        end
        
        function clear(obj)
            cla(obj.axesHandle(1)); cla(obj.axesHandle(2));
            obj.F1 = []; obj.P1 = []; obj.F2 = [];
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            obj.epochNum = obj.epochNum + 1;
            
            if isempty(obj.temporalFrequency)
                tempFreq = epoch.parameters('temporalFrequency');
            else
                tempFreq = obj.temporalFrequency;
            end
            
            response = epoch.getResponse(obj.device);
            quantities = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            prePts = obj.preTime * 1e-3 * sampleRate;
            stimFrames = obj.stimTime * 1e-3 * obj.BINRATE;
            
            if isempty(obj.xName)
                xval = obj.epochNum;
            else
                xval = epoch.parameters(obj.xName);
            end
            xIndex = obj.xvals == xval;
            
            if numel(quantities) > 0
                y = quantities;
                if strcmp(obj.onlineAnalysis, 'extracellular')
                    res = edu.washington.riekelab.patterson.utils.spikeDetectorOnline(y, [], sampleRate);
                    y = zeros(size(y));
                    y(res.sp) = 1;
                    y = edu.washington.riekelab.patterson.utils.binSpikeRate(...
                        y(prePts+1:end), obj.BINRATE, sampleRate);
                else
                    if prePts > 0
                        y = y - median(y(1:prePts));
                    else
                        y = y - median(y);
                    end
                    y = edu.washington.riekelab.patterson.utils.binData(...
                        y(prePts+1:end), obj.BINRATE, sampleRate);
                end
                
                obj.repsPerX(xIndex) = obj.repsPerX(xIndex) + 1;
                binSize = obj.BINRATE / tempFreq;
                numBins = floor(stimFrames/binSize);
                avgCycle = zeros(1, floor(binSize));
                for k = 1:numBins
                    index = round((k-1)*binSize) + (1:floor(binSize));
                    index(index > length(y)) = [];
                    ytmp = y(index);
                    avgCycle = avgCycle + ytmp(:)';
                end
                avgCycle = avgCycle / numBins;
                
                ft = fft(avgCycle);
                obj.F1(xIndex) = (obj.F1(xIndex) * (obj.repsPerX(xIndex)-1)... 
                    + abs(ft(2)) / length(avgCycle)*2) / obj.repsPerX(xIndex);
                obj.F2(xIndex) = (obj.F2(xIndex) * (obj.repsPerX(xIndex)-1)...
                    + abs(ft(3)) / length(avgCycle)*2) / obj.repsPerX(xIndex);
                obj.P1(xIndex) = (obj.P1(xIndex) * (obj.repsPerX(xIndex)-1)...
                    + angle(ft(2))) / obj.repsPerX(xIndex);
            end
            
            cla(obj.axesHandle(1)); cla(obj.axesHandle(2));
            
            line(obj.xvals, obj.F1,...
                'Parent', obj.axesHandle(1),...
                'Marker', 'o', 'Color', 'k');
            if obj.showF2
                line(obj.xvals, obj.F2,...
                    'Parent', obj.axesHandle(1),...
                    'Marker', 'o', 'Color', [0.5, 0.5, 0.5]);
            end
            line(obj.xvals, obj.P1,...
                'Parent', obj.axesHandle(2),...
                'Color', 'k', 'Marker', 'o');
            
            %xlim(obj.axesHandle(:), [min(obj.xvals), max(obj.xvals)]);            
        end
    end
    
    methods (Access = private)
        function onSelectedCaptureFigure(obj, ~, ~)
            [fileName, pathName] = uiputfile('bar.png', 'Save result as');
            if ~ischar(fileName) || ~ischar(pathName)
                return;
            end
            print(obj.figureHandle, [pathName, fileName], '-dpng', '-r600');
        end
    end
end