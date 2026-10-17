#include "sid_prepare.h"

#include <cassert>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <utility>

using megavgm_playlist::PosixSidPreparer;

namespace {

std::string make_directory()
{
	char pattern[] = "/tmp/megavgm-sid-cancel-XXXXXX";
	char *path = mkdtemp(pattern);
	assert(path);
	return path;
}

void write_script(const std::string &path, const std::string &body)
{
	std::ofstream file(path);
	file << "#!/bin/sh\n" << body;
	file.close();
	assert(file.good());
	assert(chmod(path.c_str(), 0700) == 0);
}

pid_t wait_for_pid(const std::string &path)
{
	for (unsigned attempt = 0; attempt < 200; ++attempt) {
		std::ifstream file(path);
		long value = 0;
		if (file >> value) return static_cast<pid_t>(value);
		usleep(10000);
	}
	assert(false && "converter fixture did not publish its PID");
	return -1;
}

void assert_gone(pid_t pid)
{
	errno = 0;
	assert(kill(pid, 0) < 0 && errno == ESRCH);
}

void touch(const std::string &path)
{
	std::ofstream file(path);
	file << "fixture\n";
	file.close();
	assert(file.good());
}

void assert_exists(const std::string &path)
{
	struct stat attributes = {};
	assert(lstat(path.c_str(), &attributes) == 0);
}

megavgm_playlist::SidPreparePollResult wait_for_result(
		PosixSidPreparer &preparer, std::string &detail)
{
	std::string prepared;
	for (unsigned attempt = 0; attempt < 200; ++attempt) {
		const auto result = preparer.poll(prepared, detail);
		if (result != megavgm_playlist::SidPreparePollResult::Running) return result;
		usleep(10000);
	}
	assert(false && "converter fixture did not exit");
	return megavgm_playlist::SidPreparePollResult::Failed;
}

} // namespace

int main()
{

    {
        const std::string tmp=make_directory(), converter=tmp+"/receipt.sh", prepared=tmp+"/prepared.nsf";
        std::ofstream(prepared)<<"fixture";
        const std::string h(64,'a');
        const std::string base="NATIVE_TIMING_V1 NSFe "+h+" "+h+" 1 ";
        for(const auto &row:std::vector<std::pair<std::string,long long>>{
            {"0 0",0},{"0 -",100},{"89 1850",1939},{"- 100",-1},
            {"2147483647 2147483647",4294967294LL},{"-1 100",-2},{"2147483648 1",-2},
            {"0 0 extra",-2},{"0",-2}}) {
            write_script(converter,"echo '"+prepared+"'\necho '"+base+row.first+"'\n");
            PosixSidPreparer p(converter,tmp,"",".nsf",true);std::string path,d;
            assert(p.start(tmp+"/original.nsfe",d));
            auto result=megavgm_playlist::SidPreparePollResult::Running;
            for(int i=0;i<2000&&result==megavgm_playlist::SidPreparePollResult::Running;i++){
                result=p.poll(path,d);usleep(1000);}
            if(row.second==-2)assert(result==megavgm_playlist::SidPreparePollResult::Failed);
            else {if(result!=megavgm_playlist::SidPreparePollResult::Ready)std::cerr<<row.first<<": "<<d<<"\n";assert(result==megavgm_playlist::SidPreparePollResult::Ready);
                assert(p.playback_timing().valid==(row.second>=0));
                if(row.second>=0)assert(p.playback_timing().target_ms==static_cast<std::uint64_t>(row.second));
                p.cancel();assert(!p.playback_timing().valid);}
        }
        unlink(converter.c_str());unlink(prepared.c_str());rmdir(tmp.c_str());
        std::cout<<"Owned native timing receipt: boundaries/unknown/default/malformed/cancel PASS\n";
    }
	const std::string root = make_directory();
	std::string detail;

	// A cooperative converter exits during the bounded SIGTERM grace period.
	const std::string graceful = root + "/graceful.sh";
	const std::string graceful_pid = root + "/graceful.pid";
	const std::string graceful_marker = root + "/graceful.term";
	const std::string cooperative_key(64, 'a');
	write_script(graceful,
		"trap 'echo TERM > " + graceful_marker + "; exit 0' TERM\n"
		"touch " + root + "/" + cooperative_key + ".mvgmsid.tmp.$$\n"
		"echo $$ > " + graceful_pid + "\n"
		"while :; do :; done\n");
	PosixSidPreparer cooperative(graceful, root, "");
	assert(cooperative.start(root + "/source.sid", detail));
	const pid_t cooperative_pid = wait_for_pid(graceful_pid);
	const std::string cooperative_temp = root + "/" + cooperative_key + ".mvgmsid.tmp." +
		std::to_string(cooperative_pid);
	assert_exists(cooperative_temp);

	// Exact child-PID matching removes only a regular payload temp. Formal
	// cache entries, locks, other-PID temps, near matches, symlinks, and
	// directories all remain untouched.
	const std::string formal_payload = root + "/formal.mvgmsid";
	const std::string formal_json = root + "/formal.json";
	const std::string formal_lock = root + "/formal.lock";
	const std::string other_pid = root + "/" + std::string(64, 'b') + ".mvgmsid.tmp.424242";
	const std::string near_match = cooperative_temp + ".extra";
	const std::string symlink_target = root + "/symlink-target";
	const std::string matching_symlink = root + "/" + std::string(64, 'c') + ".mvgmsid.tmp." +
		std::to_string(cooperative_pid);
	const std::string matching_directory = root + "/" + std::string(64, 'd') + ".mvgmsid.tmp." +
		std::to_string(cooperative_pid);
	const std::string invalid_key_temp = root + "/not-a-cache-key.mvgmsid.tmp." +
		std::to_string(cooperative_pid);
	for (const auto &path : {formal_payload, formal_json, formal_lock,
		other_pid, near_match, symlink_target, invalid_key_temp}) touch(path);
	assert(symlink(symlink_target.c_str(), matching_symlink.c_str()) == 0);
	assert(mkdir(matching_directory.c_str(), 0700) == 0);
	assert(cooperative.cancel().empty());
	assert(access(graceful_marker.c_str(), F_OK) == 0);
	assert_gone(cooperative_pid);
	assert(access(cooperative_temp.c_str(), F_OK) < 0 && errno == ENOENT);
	for (const auto &path : {formal_payload, formal_json, formal_lock,
		other_pid, near_match, invalid_key_temp, matching_symlink, matching_directory}) assert_exists(path);

	// A converter that ignores SIGTERM is killed and reaped after the fixed
	// grace period, so cancellation remains bounded.
	const std::string stubborn = root + "/stubborn.sh";
	const std::string stubborn_pid = root + "/stubborn.pid";
	const std::string forced_key(64, 'e');
	write_script(stubborn,
		"trap '' TERM\n"
		"touch " + root + "/" + forced_key + ".mvgmsid.tmp.$$\n"
		"echo $$ > " + stubborn_pid + "\n"
		"while :; do :; done\n");
	PosixSidPreparer forced(stubborn, root, "");
	assert(forced.start(root + "/source.sid", detail));
	const pid_t forced_pid = wait_for_pid(stubborn_pid);
	const std::string forced_temp = root + "/" + forced_key + ".mvgmsid.tmp." +
		std::to_string(forced_pid);
	assert_exists(forced_temp);
	const auto started = std::chrono::steady_clock::now();
	assert(forced.cancel().empty());
	const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::steady_clock::now() - started).count();
	assert(elapsed >= 400 && elapsed < 2000);
	assert_gone(forced_pid);
	assert(access(forced_temp.c_str(), F_OK) < 0 && errno == ENOENT);

	// A non-Ready process result also reaps first and removes only its own
	// payload temp before returning Failed.
	const std::string failed = root + "/failed.sh";
	const std::string failed_pid_path = root + "/failed.pid";
	const std::string failed_key(64, 'f');
	write_script(failed,
		"touch " + root + "/" + failed_key + ".mvgmsid.tmp.$$\n"
		"echo $$ > " + failed_pid_path + "\n"
		"exit 9\n");
	PosixSidPreparer failed_preparer(failed, root, "");
	assert(failed_preparer.start(root + "/source.sid", detail));
	const pid_t failed_pid = wait_for_pid(failed_pid_path);
	assert(wait_for_result(failed_preparer, detail) ==
		megavgm_playlist::SidPreparePollResult::Failed);
	const std::string failed_temp = root + "/" + failed_key + ".mvgmsid.tmp." +
		std::to_string(failed_pid);
	assert(access(failed_temp.c_str(), F_OK) < 0 && errno == ENOENT);

	// A cache-root cleanup failure is returned to the controller for logging.
	const std::string diagnostic = root + "/diagnostic.sh";
	const std::string diagnostic_pid_path = root + "/diagnostic.pid";
	write_script(diagnostic,
		"trap 'exit 0' TERM\n"
		"echo $$ > " + diagnostic_pid_path + "\n"
		"while :; do :; done\n");
	PosixSidPreparer diagnostic_preparer(diagnostic, root + "/missing-cache", "");
	assert(diagnostic_preparer.start(root + "/source.sid", detail));
	wait_for_pid(diagnostic_pid_path);
	const std::string cleanup_error = diagnostic_preparer.cancel();
	assert(cleanup_error.find("missing-cache") != std::string::npos);

    const std::string native_script=root+"/native.sh",native_pid_file=root+"/native.pid",native_key(64,'1');
    write_script(native_script,"trap 'exit 0' TERM\ntouch "+root+"/"+native_key+".nsf.tmp.$$ "+root+"/"+native_key+".nsf.json.tmp.$$\necho $$ > "+native_pid_file+"\nwhile :; do :; done\n");
    PosixSidPreparer native_preparer(native_script,root,"",".nsf");
    assert(native_preparer.start(root+"/original.nsfe",detail));const auto native_pid=wait_for_pid(native_pid_file);
    const std::string native_accepted=root+"/"+native_key+".nsf",native_other=root+"/"+native_key+".nsf.tmp.424242";
    touch(native_accepted);touch(native_other);
    assert(native_preparer.cancel().empty());assert_gone(native_pid);
    for(const auto &suffix:{".nsf.tmp.",".nsf.json.tmp."})assert(access((root+"/"+native_key+suffix+std::to_string(native_pid)).c_str(),F_OK)<0 && errno==ENOENT);
    assert_exists(native_accepted);assert_exists(native_other);
    for(const auto &path:{native_script,native_pid_file,native_accepted,native_other})unlink(path.c_str());
    std::cout<<"Native NSF payload/metadata child-PID cleanup and accepted/other-PID preservation PASS\n";
	unlink(graceful.c_str()); unlink(graceful_pid.c_str()); unlink(graceful_marker.c_str());
	unlink(stubborn.c_str()); unlink(stubborn_pid.c_str());
	unlink(failed.c_str()); unlink(failed_pid_path.c_str());
	unlink(diagnostic.c_str()); unlink(diagnostic_pid_path.c_str());
	for (const auto &path : {formal_payload, formal_json, formal_lock,
		other_pid, near_match, invalid_key_temp, matching_symlink, symlink_target}) unlink(path.c_str());
	assert(rmdir(matching_directory.c_str()) == 0);
	assert(rmdir(root.c_str()) == 0);
	std::cout << "SID preparer bounded cancellation and PID-scoped cleanup tests PASS\n";
	return 0;
}
