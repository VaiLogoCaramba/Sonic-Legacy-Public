package gameObjects;

import flixel.FlxBasic;
import flixel.FlxState;
import flixel.addons.effects.FlxTrail;
import flixel.addons.effects.chainable.FlxWaveEffect;
import flixel.group.*;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxTween;
import haxe.Json;
import haxe.format.JsonParser;
import meta.data.scripts.*;
import meta.data.*;
import meta.data.Song.SwagSong;
import meta.state.*;
import meta.data.StageData.StageFile;




class Stage extends FlxTypedGroup<FlxBasic>
{
	public var stageScripts:Array<FunkinScript> = [];
	public var hscriptArray:Array<FunkinHScript> = [];
	#if LUA_ALLOWED
	public var luaArray:Array<FunkinLua> = [];
	#end
	
	public var curStage = "stage1";
	public var stageData:StageFile = {
		directory: "",
        isPixelStage: false,
		defaultZoom: 0.8,
		boyfriend: [500, 100],
		girlfriend: [0, 100],
		opponent: [-500, 100],
		hide_girlfriend: false,
		camera_boyfriend: [0, 0],
		camera_opponent: [0, 0],
		camera_girlfriend: [0, 0],
		camera_speed: 1
	};

	public var spriteMap = new Map<String, FlxBasic>();
	public var foreground = new FlxTypedGroup<FlxBasic>();

	public function new(?StageName = "stage")
	{
		super();

		if (StageName != null)
			curStage = StageName;
		
		var newStageData = StageData.getStageFile(curStage);
		if (newStageData != null)
			stageData = newStageData;
	}

	public function buildStage()
	{
		var doPush:Bool = false;
		var baseScriptFile:String = 'stages/' + curStage;

		#if LUA_ALLOWED
		for (ext in ["lua"].concat(FunkinHScript.hscriptExts))
		{	
			if (doPush)
				break;
			var baseFile = '$baseScriptFile.$ext';
		#else
			var baseFile = '$baseScriptFile.hscript';
		#end

			var files =
			for (file in files)
			{
				if (Paths.exists(file,TEXT))
				{
					#if LUA_ALLOWED
					if (FunkinHScript.hscriptExts.contains(ext)){
					#end
	
						var script = FunkinHScript.fromFile(file);

						hscriptArray.push(script);
						stageScripts.push(script);

						// define variables lolol
						script.set("add", add);
						script.set("stage", this);
						script.set("foreground", foreground);
						
						script.call("onLoad", [this, foreground]);
						doPush = true;
					#if LUA_ALLOWED
					} else if (ext == 'lua'){
						var script = new FunkinLua(file);
						luaArray.push(script);
						stageScripts.push(script);
						
						script.call("onCreate", []);
						doPush = true;
					}
					else
					#end

					if (doPush)
						break;
				}
			}
		#if LUA_ALLOWED
		}
		#end
		// return this;
	}

	public function buildSimple(){
		var doPush:Bool = false;
		var baseScriptFile:String = 'stages/' + curStage;

		for (ext in ["lua"].concat(FunkinHScript.hscriptExts))
		{
			if (doPush)
				break;
			var baseFile = '$baseScriptFile.$ext';

			var files = [Paths.modFolders(baseFile), Paths.getPreloadPath(baseFile)];
			for (file in files)
			{
				trace(file);
				if (Paths.exists(file,TEXT))
				{
					if (FunkinHScript.hscriptExts.contains(ext)){
						var script = FunkinHScript.fromFile(file);
						trace(file);

						// define variables lolol
						script.set("add", add);
						script.set("stage", this);
						script.set("foreground", foreground);
						
						script.call("onLoad", [this, foreground]);
						// doPush = true;
						break;
					} else if (ext == 'lua'){
						var script = new FunkinLua(file);
						luaArray.push(script);
						stageScripts.push(script);
						
						script.call("onCreate", []);
						// doPush = true;
						break;
					}
					else

					if (doPush)
						break;
				}
			}
		}
	}

	override function destroy(){
		for (script in stageScripts)
			script.stop();
		super.destroy();
	}

	//// Stages of the currently loaded mod.
	// public static function getStageList(modsOnly = false):Array<String>{
	// 	var rawList:Null<String> = modsOnly ? null : Paths.txt('data/stageList.txt', true);

	// 	#if MODS_ALLOWED
	// 	var modsList = Paths.txt('data/stageList.txt', false);
	// 	if (modsList != null){
	// 		if (rawList != null)
	// 			rawList += "\n" + modsList;
	// 		else
	// 			rawList = modsList;
	// 	}
	// 	#end
		
	// 	if (rawList == null)
	// 		return [];

	// 	var stages:Array<String> = [];

	// 	for (i in rawList.trim().split('\n'))
	// 	{
	// 		var modStage = i.trim();
	// 		if (!stages.contains(modStage))
	// 			stages.push(modStage);
	// 	}

	// 	return stages;
	// }

	/*
	//// stage -> modDirectory
	public static function getStageMap():Map<String, String>
	{
		var directories:Array<String> = [
			#if MODS_ALLOWED
			Paths.mods(Paths.currentModDirectory + '/stages/'),
			Paths.mods('stages/'),
			#end
			Paths.getPreloadPath('stages/')
		];

		var theMap:Map<String, String> = new Map();

		return theMap;
	}
	*/
}

class StageData {
	public static var forceNextDirectory:String = null;

	public static function loadDirectory(SONG:SwagSong) {
		var stage:String = '';

		if(SONG.stage != null)
			stage = SONG.stage;
		else 
			stage = 'stage';

		var stageFile:StageFile = getStageFile(stage);

		// preventing crashes
		forceNextDirectory = stageFile == null ? '' : stageFile.directory;
	}

	public static function getStageFile(stage:String):StageFile {
		var rawJson:String = null;
		var path:String = Paths.getPreloadPath('stages/' + stage + '.json');

		#if MODS_ALLOWED
		var modPath:String = Paths.modFolders('stages/' + stage + '.json');

		if(Paths.exists(modPath))
			rawJson = Paths.getContent(modPath);
		else if(Paths.exists(path))
			rawJson = Paths.getContent(path);

		#else
		if(Assets.exists(path))
			rawJson = Assets.getText(path);
		#end
		else
			return null;

		trace(rawJson);

		trace(path);

		return cast Json.parse(rawJson);
	}
}
