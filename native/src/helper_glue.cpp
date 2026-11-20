#include <mutex>
#include <cstdio>
// Simulator Stages level helper: this mod's own part. tools/make_helper_source.py stitches it together with
// sections copied from Junon Colosseum's helper to make main.cpp.
//
// What it does: UE4SS 3.0.1's Lua cannot call LevelStreamingDynamic.LoadLevelInstance (the function's bool
// out-parameter breaks the Lua argument stack), so this helper makes that one call. The Lua side writes requests to
// stages-request.txt in the mod's folder; the helper takes them on the game thread, at a Blueprint tick, one per
// frame, while the package loader is idle, and writes the outcome to stages-ack.txt. It also writes
// stages-helper.txt twice a second so the Lua side can tell it is alive and able to work.
//
// It reads no game memory beyond what the copied sections check byte for byte, writes none, and changes no save.
//
// Proton (2026-11-19). A Steam player on Linux (Proton) crashed as the game started, within 90 ms of this helper's
// "ready" line, before any of the mod's Lua ran; Windows never did. We could not run Proton, so 1.3.0 removes every
// way this helper could touch the game early:
//   - the checks on the game's code (and the pattern searches a Steam copy needs) run once, in on_unreal_init, on
//     UE4SS's own thread, under an exception guard; they used to run on the game thread at its first Blueprint tick;
//   - nothing runs on the game thread until ArmDelay after start-up, long before anyone reaches the simulator;
//   - the game thread never writes to UE4SS's log: lines are queued and written by UE4SS's thread (on_update);
//   - each step is written to stages-helper-trace.txt in the mod's folder as it happens, so a crash leaves a record
//     of how far the helper got.
namespace
{
    std::atomic<bool> faulted{false};
    std::string Shared(const char* name);   // below, with the other file paths
    const ULONGLONG startedAt=GetTickCount64();
    std::mutex traceLock;
    // One line to stages-helper-trace.txt, opened, written and closed each time so it survives a crash. Rare
    // events only (start-up steps, firsts, requests); never per frame.
    void Trace(const std::string& line) noexcept
    {
        try {
            std::lock_guard<std::mutex> hold(traceLock);
            FILE* file=nullptr;
            if(fopen_s(&file,Shared("stages-helper-trace.txt").c_str(),"ab") || !file) return;
            fprintf(file,"%llu ms\tthread %lu\t%s\n",GetTickCount64()-startedAt,GetCurrentThreadId(),line.c_str());
            fflush(file);
            fclose(file);
        } catch(...) {}
    }
    std::mutex sayLock;
    std::vector<std::string> unsaid;
    // A line for UE4SS's log. Any thread may call this; Flush() writes the lines from UE4SS's own thread.
    void Say(const std::string& line) noexcept
    {
        Trace("say: "+line);
        try {
            std::lock_guard<std::mutex> hold(sayLock);
            if(unsaid.size()<64) unsaid.push_back("[SimulatorStages] "+line+"\n");
        } catch(...) {}
    }
    void Flush() noexcept
    {
        std::vector<std::string> lines;
        try {
            std::lock_guard<std::mutex> hold(sayLock);
            lines.swap(unsaid);
        } catch(...) { return; }
        for(const auto& message:lines){
            printf_s("%s",message.c_str());
            try {
                const std::wstring wide(message.begin(),message.end());
                RC::Output::send(std::wstring_view(wide));
            } catch(...) {}
        }
    }
    // A check on the game's code failed: say so once and do no engine work. Junon Colosseum shows a window here;
    // this mod only loses its streamed stages, so a log line is enough.
    void Fault(const char* code,const std::string& logLine,const std::wstring&) noexcept
    {
        if(!faulted.exchange(true)) Say(std::string(code)+": "+logLine+" Streamed stages are off.");
    }
// ==== COPIED SECTIONS GO HERE ====
    // ---- this mod's own request loop ----

    // LevelStreamingDynamic.LoadLevelInstance(WorldContextObject, LevelName, Location, Rotation, bOutSuccess,
    // OptionalLevelNameOverride), through reflection: every offset and size comes from the function's own
    // properties, as in Junon Colosseum's LoadOwnedLevel, which leaves Location and Rotation at zero. Here they are
    // set: a stage's levels are placed so that its fight centre lands on the simulator's centre.
    RC::Unreal::UObject* LoadLevel(RC::Unreal::UObject* context,const std::wstring& packagePath,const std::wstring& instanceName,
                                   float x,float y,float z,float yaw,std::string& why)
    {
        using namespace RC::Unreal;
        auto* api=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,STR("/Script/Engine.Default__LevelStreamingDynamic"));
        auto* fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Engine.LevelStreamingDynamic:LoadLevelInstance"));
        if(!api || !fn){ why="function_or_default_missing"; return nullptr; }
        if(fn->GetNumParms()!=7 || fn->GetPropertiesSize()<8 || fn->GetPropertiesSize()>256){ why="unexpected_parameter_block"; return nullptr; }
        struct Parameters {
            std::vector<uint8_t> bytes;
            std::vector<FProperty*> fields;
            ~Parameters(){for(auto it=fields.rbegin();it!=fields.rend();++it)(*it)->DestroyValue_InContainer(bytes.data());}
        } params{std::vector<uint8_t>(fn->GetPropertiesSize()),{}};
        FProperty *world=nullptr,*path=nullptr,*location=nullptr,*rotation=nullptr,*success=nullptr,*name=nullptr,*result=nullptr;
        for(auto* field:fn->ForEachProperty()){
            if(!field->HasAnyPropertyFlags(CPF_Parm))continue;
            if(field->GetArrayDim()!=1 || field->GetOffset_Internal()<0 || field->GetElementSize()<1 ||
               field->GetOffset_Internal()+field->GetElementSize()>fn->GetPropertiesSize()){ why="field_outside_parameter_block"; return nullptr; }
            field->InitializeValue_InContainer(params.bytes.data());params.fields.push_back(field);
            const auto n=field->GetName();
            if(n==STR("WorldContextObject"))world=field;
            else if(n==STR("LevelName"))path=field;
            else if(n==STR("Location"))location=field;
            else if(n==STR("Rotation"))rotation=field;
            else if(n==STR("bOutSuccess"))success=field;
            else if(n==STR("OptionalLevelNameOverride"))name=field;
            else if(n==STR("ReturnValue"))result=field;
            else { why="unknown_parameter"; return nullptr; }
        }
        if(params.fields.size()!=7 || !world || !path || !name || !location || !rotation || !success || !result ||
           !world->IsA<FObjectProperty>() || !path->IsA<FStrProperty>() || !name->IsA<FStrProperty>() ||
           !location->IsA<FStructProperty>() || !rotation->IsA<FStructProperty>() ||
           !success->IsA<FBoolProperty>() || !result->IsA<FObjectProperty>() ||
           location->GetElementSize()!=12 || rotation->GetElementSize()!=12 ||
           world->GetElementSize()!=sizeof(UObject*) || result->GetElementSize()!=sizeof(UObject*) ||
           path->GetElementSize()!=sizeof(FString) || name->GetElementSize()!=sizeof(FString)){ why="parameter_type_or_size"; return nullptr; }
        FString package(packagePath.c_str());
        FString leaf(instanceName.c_str());
        world->CopySingleValue(world->ContainerPtrToValuePtr<void>(params.bytes.data()),&context);
        path->CopySingleValue(path->ContainerPtrToValuePtr<void>(params.bytes.data()),&package);
        name->CopySingleValue(name->ContainerPtrToValuePtr<void>(params.bytes.data()),&leaf);
        // FVector is X, Y, Z and FRotator is Pitch, Yaw, Roll: three floats each (sizes checked above).
        const float where[3]={x,y,z};
        const float turn[3]={0.0f,yaw,0.0f};
        std::memcpy(location->ContainerPtrToValuePtr<void>(params.bytes.data()),where,sizeof where);
        std::memcpy(rotation->ContainerPtrToValuePtr<void>(params.bytes.data()),turn,sizeof turn);
        api->ProcessEvent(fn,params.bytes.data());
        const bool ok=static_cast<FBoolProperty*>(success)->GetPropertyValueInContainer(params.bytes.data());
        UObject* stream=*result->ContainerPtrToValuePtr<UObject*>(params.bytes.data());
        if(!ok) why="load_refused";
        else if(!stream) why="no_stream_returned";
        return ok ? stream : nullptr;
    }
    // LevelStreaming.SetIsRequestingUnloadAndRemoval(true) on a stream this helper loaded: one bool parameter,
    // its type taken from the function's own properties.
    bool UnloadStream(RC::Unreal::UObject* stream,std::string& why)
    {
        using namespace RC::Unreal;
        auto* fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Engine.LevelStreaming:SetIsRequestingUnloadAndRemoval"));
        if(!fn){ why="function_missing"; return false; }
        if(fn->GetNumParms()!=1 || fn->GetPropertiesSize()<1 || fn->GetPropertiesSize()>16){ why="unexpected_parameter_block"; return false; }
        std::vector<uint8_t> bytes(fn->GetPropertiesSize());
        FProperty* flag=nullptr;
        for(auto* field:fn->ForEachProperty()) if(field->HasAnyPropertyFlags(CPF_Parm)) flag=field;
        if(!flag || !flag->IsA<FBoolProperty>()){ why="parameter_type"; return false; }
        static_cast<FBoolProperty*>(flag)->SetPropertyValueInContainer(bytes.data(),true);
        stream->ProcessEvent(fn,bytes.data());
        return true;
    }

    // Requests, game thread only. A line of stages-request.txt is: load <tab> name <tab> package <tab> x <tab> y
    // <tab> z <tab> yaw, or: unload <tab> name. The file is renamed before it is read, so a request written meanwhile is not lost.
    struct Request { bool unload=false; std::wstring package, name; float x=0,y=0,z=0,yaw=0; ULONGLONG at=0; };
    std::vector<Request> queue;
    // The streams this helper loaded, by instance name, so it can unload them. Only the address is kept (live
    // 2026-11-17: a weak pointer assigned here never resolved again); before it is used, StillThere() confirms it
    // is still one of the game's LevelStreamingDynamic objects.
    std::unordered_map<std::wstring,RC::Unreal::UObject*> streams;
    bool StillThere(RC::Unreal::UObject* wanted)
    {
        std::vector<RC::Unreal::UObject*> all;
        RC::Unreal::UObjectGlobals::FindAllOf(STR("LevelStreamingDynamic"),all);
        return std::find(all.begin(),all.end(),wanted)!=all.end();
    }
    constexpr ULONGLONG MaxDefer=8000;   // ms a request waits for the loader to go idle before it is served anyway
    constexpr size_t MaxQueue=64;

    void Ack(const std::wstring& name,const std::string& result)
    {
        std::ofstream out(Shared("stages-ack.txt"),std::ios::app);
        out<<std::string(name.begin(),name.end())<<"\t"<<result<<"\n";
    }
    void Intake(ULONGLONG now)
    {
        static ULONGLONG next=0;
        if(now<next) return;
        next=now+200;
        std::error_code ec;
        const std::filesystem::path request=Shared("stages-request.txt"), taken=Shared("stages-request.taken");
        if(!std::filesystem::exists(request,ec)) return;
        std::filesystem::remove(taken,ec);
        std::filesystem::rename(request,taken,ec);
        if(ec) return;
        std::ifstream in(taken);
        std::string line;
        while(std::getline(in,line)){
            while(!line.empty() && (line.back()=='\r' || line.back()==' ')) line.pop_back();
            std::vector<std::string> part;
            std::stringstream fields(line);
            std::string field;
            while(std::getline(fields,field,'\t')) part.push_back(field);
            if(part.size()==2 && part[0]=="unload"){
                Request u;
                u.unload=true;
                u.name.assign(part[1].begin(),part[1].end());
                u.at=now;
                if(queue.size()<MaxQueue) queue.push_back(u);
                continue;
            }
            if(part.size()!=7 || part[0]!="load") continue;
            Request r;
            r.name.assign(part[1].begin(),part[1].end());
            r.package.assign(part[2].begin(),part[2].end());
            try { r.x=std::stof(part[3]); r.y=std::stof(part[4]); r.z=std::stof(part[5]); r.yaw=std::stof(part[6]); }
            catch(...) { Ack(r.name,"refused\tbad_number"); continue; }
            // Only this game's own level packages, and a plain instance name.
            const bool plainName=!r.name.empty() && r.name.size()<=96 &&
                std::all_of(r.name.begin(),r.name.end(),[](wchar_t c){ return (c>=L'A'&&c<=L'Z')||(c>=L'a'&&c<=L'z')||(c>=L'0'&&c<=L'9')||c==L'_'; });
            if(r.package.rfind(L"/Game/Level/",0)!=0 || r.package.size()>300 || !plainName){ Ack(r.name,"refused\tbad_request"); continue; }
            if(queue.size()>=MaxQueue){ Ack(r.name,"refused\tqueue_full"); continue; }
            r.at=now;
            queue.push_back(r);
        }
        in.close();
        std::filesystem::remove(taken,ec);
    }
    // Twice a second: proof for the Lua side that the helper is running on the game thread and its checks passed.
    void Beat(ULONGLONG now,bool loading)
    {
        static ULONGLONG next=0;
        if(now<next) return;
        if(!next) Trace(std::string("game thread: first heartbeat, ready ")+(Loader::Verify()&&!faulted.load()?"1":"0"));
        next=now+500;
        const std::string path=Shared("stages-helper.txt");
        {
            std::ofstream out(path+".tmp",std::ios::trunc);
            out<<"tick\t"<<now<<"\nready\t"<<(Loader::Verify()&&!faulted.load()?1:0)<<"\nloading\t"<<(loading?1:0)<<"\nqueued\t"<<queue.size()<<"\n";
        }
        std::error_code ec;
        std::filesystem::rename(path+".tmp",path,ec);
    }
    // Every game-thread ProcessEvent of a Blueprint tick or camera update: take new requests, and serve at most one.
    void AtSafePoint(RC::Unreal::UObject* object,RC::Unreal::UFunction* function,const char* kind)
    {
        thread_local bool busy=false;   // the load re-enters ProcessEvent
        if(busy) return;
        busy=true;
        try {
            const ULONGLONG now=GetTickCount64();
            const bool verified=Loader::Verify() && !faulted.load();
            const bool loading=verified && Loader::Busy();
            Beat(now,loading);
            if(verified){
                Intake(now);
                // The world context has to be an actor in the world: an actor's own tick.
                const bool actorTick=std::strcmp(kind,"receive_tick")==0 && object && object->IsA<RC::Unreal::AActor>();
                if(!queue.empty() && actorTick && SafePoint::Open(object,function) &&
                   (!loading || (!queue.front().unload && now-queue.front().at>=MaxDefer))){   // an unload searches the game's objects: only while idle
                    const Request r=queue.front();
                    queue.erase(queue.begin());
                    std::string why;
                    bool ok=false;
                    try {
                        if(r.unload){
                            const auto found=streams.find(r.name);
                            RC::Unreal::UObject* stream=found==streams.end()?nullptr:found->second;
                            if(!stream) why="not_loaded_by_helper";
                            else if(!StillThere(stream)) why="already_gone";
                            else ok=UnloadStream(stream,why);
                            if(found!=streams.end()) streams.erase(found);
                        }else{
                            RC::Unreal::UObject* stream=LoadLevel(object,r.package,r.name,r.x,r.y,r.z,r.yaw,why);
                            ok=stream!=nullptr;
                            if(ok) streams[r.name]=stream;
                        }
                    }
                    catch(const std::exception& error) { why=std::string("cpp_exception ")+error.what(); }
                    catch(...) { why="cpp_exception"; }
                    Ack(r.name,ok?std::string(r.unload?"unloaded":"loaded")+"\t"+std::to_string(now-r.at)+"ms":"refused\t"+why);
                    static int traced=0;   // the first few requests, as a record of how far a session got
                    if(traced<4){ ++traced; Trace(std::string(r.unload?"unload ":"load ")+std::string(r.name.begin(),r.name.end())+": "+(ok?"ok":why)); }
                    SafePoint::Close(object,function);
                }
            }
        } catch(...) {}
        busy=false;
    }

    // Start-up checks on the game's code, run on UE4SS's thread before the game-thread callback can do anything.
    // Resolves the game-thread slot (OnGameThread's first call; false on this thread) and verifies the loader.
    void CheckGame() { OnGameThread(); Loader::Verify(); }
    // Plain function (no C++ objects) so __try may guard it. False if a read faulted; the caller then turns streamed
    // stages off, so nothing touched by the interrupted checks is used again.
    bool CheckGameGuarded() noexcept
    {
        __try { CheckGame(); return true; }
        __except(1) { return false; }
    }
    constexpr ULONGLONG ArmDelay=10000;   // ms after start-up before the game thread does any of this helper's work
    std::atomic<ULONGLONG> armAt{0};      // 0: never (the checks failed)
    bool Armed() noexcept
    {
        static std::atomic<bool> armed{false};
        if(armed.load(std::memory_order_relaxed)) return true;
        const ULONGLONG at=armAt.load();
        if(!at || GetTickCount64()<at) return false;
        if(!armed.exchange(true)) Trace("armed: game-thread work allowed from now");
        return true;
    }

    class SimulatorStagesHelper : public RC::CppUserModBase
    {
    public:
        SimulatorStagesHelper()
        {
            ModName = STR("Simulator Stages level helper");
            ModVersion = STR("1.3.0");
            ModDescription = STR("Loads a stage's levels at the combat simulator's position for the Simulator Stages mod");
            ModAuthors = STR("CaitGPT");
        }
        void on_unreal_init() override
        {
            std::error_code ec;
            std::filesystem::remove(Shared("stages-request.txt"),ec);   // nothing left over from an earlier run
            std::filesystem::remove(Shared("stages-ack.txt"),ec);
            std::filesystem::remove(Shared("stages-helper.txt"),ec);
            std::filesystem::remove(Shared("stages-helper-trace.txt"),ec);
            Trace("start: helper 1.3.0");
            SafePoint::Init();
            Trace("start: names found");
            const bool checked=CheckGameGuarded();
            Trace(checked ? (faulted.load() ? "start: game checks done, streamed stages off" : "start: game checks done")
                          : "start: game checks faulted, streamed stages off");
            if(!checked) Fault("SS-CHECK","reading the game's code failed.",L"");
            RC::Unreal::Hook::RegisterProcessEventPreCallback([](auto* object,auto* function,void*) {
                const char* kind=SafePoint::Kind(function);
                if(!kind) return;                 // a name compare on every ProcessEvent, nothing more
                if(!Armed()) return;              // nothing on the game thread until ArmDelay after start-up
                if(!OnGameThread()) return;       // engine work only where the loader keeps its state
                AtSafePoint(object,function,kind);
            });
            Trace("start: callback registered");
            if(!faulted.load()) armAt.store(GetTickCount64()+ArmDelay);
            Say("level helper ready");
            Flush();
        }
        void on_update() override { Flush(); }
    };
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new SimulatorStagesHelper(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
