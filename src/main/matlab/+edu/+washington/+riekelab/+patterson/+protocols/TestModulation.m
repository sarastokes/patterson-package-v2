classdef TestModulation < edu.washington.riekelab.protocols.RiekeLabProtocol

    properties 
        led 
        preTime = 500
        stimTime = 2500
        tailTime = 500
        temporalFrequency = 4
        backgroundIntensity = 0.5
        contrasts = [0.02, 0.02, 0.02, 0.05, 0.05, 0.05, 0.1, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.4, 0.4, 0.5, 0.8, 1];
        onlineAnalysis = 'none'
        numberOfAverages = uint16(18)
        interpulseInterval = 0
        amp 
    end

    properties (Hidden)
        ledType 
        ampType 
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'})

        contrast 
    end

    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);

            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9', 'length', numel(unique(obj.contrasts)));

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp), 'groupBy', {'contrast'},...
                'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.patterson.figures.F1F2Figure',...
                    obj.rig.getDevice(obj.amp), unique(obj.contrasts), obj.onlineAnalysis,...
                    obj.preTime, obj.stimTime, 'temporalFrequency', obj.temporalFrequency,...
                    'xName', 'contrast', 'showF2', false, 'debug', true);
            end

            device1 = obj.rig.getDevice(obj.led);
            device1.background = symphonyui.core.Measurement(...
                obj.backgroundIntensity, device1.background.displayUnits);
        end

         function stim1 = createLedStimulus(obj, amplitude)

            gen = edu.washington.riekelab.patterson.stimuli.SineGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.amplitude = obj.backgroundIntensity * amplitude + obj.backgroundIntensity;
            gen.period = round(1000 / obj.temporalFrequency);
            gen.phase = 0;
            gen.mean = obj.backgroundIntensity;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;

            stim1 = gen.generate();
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            obj.contrast = obj.contrasts(obj.numEpochsCompleted+1);

            epoch.addStimulus(obj.rig.getDevice(obj.led),...
                obj.createLedStimulus(obj.contrast));
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            epoch.addParameter('contrast', obj.contrast);
        end

        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
            interval.addDirectCurrentStimulus(device,...
                device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end 
    end
end 