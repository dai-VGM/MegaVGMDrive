#pragma once

#include "supervisor.h"

#include <string>

namespace megavgm_supervisor {

class InstanceLock {
public:
	InstanceLock() = default;
	~InstanceLock();
	InstanceLock(const InstanceLock &) = delete;
	InstanceLock &operator=(const InstanceLock &) = delete;

	OperationResult acquire(const std::string &path);
	bool acquired() const { return fd_ >= 0; }

private:
	int fd_ = -1;
};

class AtomicStatusPublisher : public StatusPublisher {
public:
	explicit AtomicStatusPublisher(std::string path);
	OperationResult publish(const Snapshot &snapshot) override;
	const std::string &path() const { return path_; }

private:
	std::string path_;
};

class ControlServer {
public:
	ControlServer() = default;
	~ControlServer();
	ControlServer(const ControlServer &) = delete;
	ControlServer &operator=(const ControlServer &) = delete;

	OperationResult open(const std::string &path);
	bool exit_requested();

private:
	int fd_ = -1;
	std::string path_;
};

OperationResult send_exit_request(const std::string &path);
OperationResult request_exit_or_classify(const std::string &socket_path,
	const std::string &status_path);
bool read_text_file(const std::string &path, std::string &content,
	std::string &detail, std::size_t maximum_size = 65536);
bool status_is_stock(const std::string &content);
bool status_is_restoring(const std::string &content);

} // namespace megavgm_supervisor
